!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!!
!! Written by: 
!!
!!   Luis 'Tony' Martinez <tony.mtos@gmail.com> (Johns Hopkins University)
!!
!!   Copyright (C) 2012-2013, Johns Hopkins University
!!
!!   This file is part of The Actuator Turbine Model Library.
!!
!!   The Actuator Turbine Model is free software: you can redistribute it 
!!   and/or modify it under the terms of the GNU General Public License as 
!!   published by the Free Software Foundation, either version 3 of the 
!!   License, or (at your option) any later version.
!!
!!   The Actuator Turbine Model is distributed in the hope that it will be 
!!   useful, but WITHOUT ANY WARRANTY; without even the implied warranty of
!!   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
!!   GNU General Public License for more details.
!!
!!   You should have received a copy of the GNU General Public License
!!   along with Foobar.  If not, see <http://www.gnu.org/licenses/>.
!!
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

!*******************************************************************************
module atm_lesgo_interface
!*******************************************************************************
! This module interfaces actuator turbine module with lesgo
! It is a lesgo specific module, unlike the atm module

! Remember to always dimensinoalize the variables from LESGO
! Length is non-dimensionalized by z_i

! Lesgo data used regarding the grid (LESGO)
use param, only : dt ,nx,ny,nz,dx,dy,dz,coord,lbz,nproc, z_i, u_star
! nx, ny, nz - nodes in every direction
! z_i - non-dimensionalizing length
! dt - time-step 

! These are the forces, and velocities on x,y, and z respectively
use sim_param, only : fxa, fya, fza, u, v, w

! Grid definition (LESGO)
use grid_defs, only : grid

! Interpolating function for interpolating the velocity field to each
! actuator point
use functions, only : trilinear_interp

! Actuator Turbine Model module
use atm_base
use actuator_turbine_model
use atm_input_util, only : rprec, turbineArray, turbineModel

implicit none

private
public atm_lesgo_initialize, atm_lesgo_forcing

! This is a dynamic list that stores all the points in the domain with a body 
! force due to the turbines. 
type bodyForce_t
!     i,j,k stores the index for the point in the domain
    integer i,j,k
    real(rprec), dimension(3) :: force ! Force vector
    real(rprec), dimension(3) :: location ! Position vector
end type bodyForce_t

! Body force field
type(bodyForce_t), allocatable, dimension(:) :: forceField

contains

!+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
subroutine atm_lesgo_initialize ()
!+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
! Initialize the actuator turbine model
implicit none

! Counter to establish number of points which are influenced by body forces
integer :: c0
real(rprec) :: zeroVector(3)     ! A vector of zeros used for initiallizing vec
integer :: i, j, k, m
! Vector used to store x, y, z locations
real(rprec), dimension(3) :: vector_point
! These are the pointers to the grid arrays
real(rprec), pointer, dimension(:) :: x,y,z


! Define all elements of zero vector to zero
do i=1,3
    zeroVector(i)=0.
enddo


! Declare x, y, and z as pointers to the grid variables x, y, and z (LESGO)
nullify(x,y,z)
x => grid % x
y => grid % y
z => grid % z

call atm_initialize () ! Initialize the atm (ATM)

! This will find all the locations that are influenced by each turbine
! It depends on a sphere centered on the rotor that extends beyond the blades
c0=0  ! Initialize conuter
do k=1,nz ! Loop through grid points in z
    do j=1,ny ! Loop through grid points in y
        do i=1,nx ! Loop through grid points in x
            vector_point(1)=x(i)*z_i ! z_i used to dimensionalize LESGO
            vector_point(2)=y(j)*z_i
            vector_point(3)=z(k)*z_i
            do m=1,numberOfTurbines
                if (distance(vector_point,turbineArray(m) % baseLocation) &
                    .le. turbineArray(m) % sphereRadius ) then
                    c0=c0+1
                end if
            end do 
        end do
    end do
end do

allocate(forceField(c0))
write(*,*) 'Numebr of cells being affected by ATM = ', c0

c0=0
! Run the same loop and save all variables
do k=1,nz ! Loop through grid points in z
    do j=1,ny ! Loop through grid points in y
        do i=1,nx ! Loop through grid points in x
            vector_point(1)=x(i)*z_i ! z_i used to dimensionalize LESGO
            vector_point(2)=y(j)*z_i
            vector_point(3)=z(k)*z_i
            do m=1,numberOfTurbines
                if (distance(vector_point,turbineArray(m) % baseLocation) &
                    .le. turbineArray(m) % sphereRadius ) then
                    c0=c0+1
                    forceField(c0) % i = i
                    forceField(c0) % j = j
                    forceField(c0) % k = k
                    forceField(c0) % location = vector_point
                end if
            end do 
        end do
    end do
end do



end subroutine atm_lesgo_initialize


!+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
subroutine atm_lesgo_forcing ()
!+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
! This subroutines calls the update function from the ATM Library
! and calculates the body forces needed in the domain
integer :: i, c
write(*,*) 'dt = ', dt

! If statement is for running code only if grid points affected are in this 
! processor. If not, no code is executed at all.
if (size(forceField) .gt. 0) then

    ! Update the blade positions based on the time-step
    call atm_update(dt)

    ! Initialize force field to zero
    do c=1,size(forceField)
        forceField(c) % force = 0._rprec     
    enddo

    ! Calculate forces for all turbines
    do i=1,numberOfTurbines
        call atm_lesgo_force(i)
    enddo

write(*,*) 'Passed Time'

endif

end subroutine atm_lesgo_forcing

!+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
subroutine atm_lesgo_force(i)
!+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
! This will feed the velocity at all the actuator points into the atm
! This is done by using trilinear interpolation from lesgo
! Force will be calculated based on the velocities
implicit none

integer, intent(in) :: i ! The turbine number
integer :: m,n,q,j,c
real(rprec), dimension(3) :: velocity
real(rprec), dimension(3) :: xyz    ! Point onto which to interpolate velocity
j=turbineArray(i) % turbineTypeID ! The turbine type ID


! This loop goes through all the blade points and calculates the respective
! body forces then imposes it onto the force field
do q=1, turbineArray(i) % numBladePoints
    do n=1, turbineArray(i) % numAnnulusSections
        do m=1, turbineModel(j) % numBl
                       
            ! Actuator point onto which to interpolate the velocity
            xyz=turbineArray(i) % bladePoints(m,n,q,1:3)

            ! Non-dimensionalizes the point location 
            xyz=vector_divide(xyz,z_i)

            ! Interpolate velocities
            velocity(1)=1. ! trilinear_interp(u(1:nx,1:ny,lbz:nz),lbz,xyz)*u_star
            velocity(2)=1. ! trilinear_interp(v(1:nx,1:ny,lbz:nz),lbz,xyz)*u_star
            velocity(3)=1. ! trilinear_interp(w(1:nx,1:ny,lbz:nz),lbz,xyz)*u_star

            call atm_computeBladeForce(i,m,n,q,velocity)

            do c=1,size(forceField)
                call atm_convoluteForce(i,m,n,q,forceField(c) % location,  &
                                        forceField(c) % force)       
!                fxa(forceField(c) % i,forceField(c) % j, forceField(c) % k) = &
!                fxa(forceField(c) % i,forceField(c) % j, forceField(c) % k) + &
!                forceField(c) % force(1)/(u_star**2*z_i**2)
!write(*,*) 'xyz = ', xyz
!write(*,*) ' Force fxa= ',fxa(forceField(c) % i, forceField(c) % j, forceField(c) % k)
            enddo
        enddo
    enddo
enddo

! This loop goes through all the points affected by body forces and imposes 
! the proper body force
!do q=1, turbineArray(i) %  numBladePoints
!    do n=1, turbineArray(i) % numAnnulusSections
!        do m=1, turbineModel(j) % numBl
!            do c=1,size(forceField)


!write(*,*) 'Force is = ', fxa(forceField(c0) % i,forceField(c0) % j,forceField % k)

!            enddo
!        enddo
!    enddo
!enddo

! Impose force field onto the flow field variables
do c=1,size(forceField)
    fxa(forceField(c) % i,forceField(c) % j,forceField(c) % k) = &
    fxa(forceField(c) % i,forceField(c) % j,forceField(c) % k) + &
    forceField(c) % force(1)
!write(*,*) 'Force is = ', fxa(forceField(c) % i,forceField(c) % j,forceField(c) % k)
    fya(forceField(c) % i,forceField(c) % j,forceField(c) % k) = &
    fya(forceField(c) % i,forceField(c) % j,forceField(c) % k) + &
    forceField(c) % force(2)
    fza(forceField(c) % i,forceField(c) % j,forceField(c) % k) = &
    fza(forceField(c) % i,forceField(c) % j,forceField(c) % k) + &
    forceField(c) % force(3)
enddo

end subroutine atm_lesgo_force


end module atm_lesgo_interface
