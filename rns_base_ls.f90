!**********************************************************************
module rns_base_ls
!**********************************************************************
use types, only : rprec
use param, only : ld, ny, nz
implicit none

save
public

logical, parameter :: clforce_calc = .true.
logical, parameter :: brforce_calc = .false.

integer, parameter :: clforce_nskip = 2
!type rns
!  integer :: ntrees, nplanes
!  logical :: plane_u_calc
!end type rns

type ref_plane
  integer :: nzeta, neta ! discretization
  real(rprec), dimension(3) :: p1, p2, p3 !  3 ordered points
  real(rprec) :: u, v, w ! reference values
  real(rprec) :: area
end type ref_plane

type force
  real(rprec) :: fD
  real(rprec) :: CD
end type force

type(ref_plane), pointer, dimension(:) :: cl_ref_plane_t
type(force), pointer, dimension(:) :: brforce_t, clforce_t

logical :: brindx_initialized = .false.
integer :: brindx(ld, ny, nz)

end module rns_base_ls
