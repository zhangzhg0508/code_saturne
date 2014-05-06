!-------------------------------------------------------------------------------

!VERS

! This file is part of Code_Saturne, a general-purpose CFD tool.
!
! Copyright (C) 1998-2014 EDF S.A.
!
! This program is free software; you can redistribute it and/or modify it under
! the terms of the GNU General Public License as published by the Free Software
! Foundation; either version 2 of the License, or (at your option) any later
! version.
!
! This program is distributed in the hope that it will be useful, but WITHOUT
! ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
! FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more
! details.
!
! You should have received a copy of the GNU General Public License along with
! this program; if not, write to the Free Software Foundation, Inc., 51 Franklin
! Street, Fifth Floor, Boston, MA 02110-1301, USA.

!-------------------------------------------------------------------------------

!===============================================================================
! Function:
! ---------
!> \file  cs_user_boundary_conditions-electric_arcs.f90
!> \brief Example of cs_user_boundary_conditions subroutine.f90 for electric arcs
!
!-------------------------------------------------------------------------------

!-------------------------------------------------------------------------------
! Arguments
!______________________________________________________________________________.
!  mode           name          role                                           !
!______________________________________________________________________________!
!> \param[in]     nvar          total number of variables
!> \param[in]     nscal         total number of scalars
!> \param[out]    icodcl        boundary condition code:
!>                               - 1 Dirichlet
!>                               - 2 Radiative outlet
!>                               - 3 Neumann
!>                               - 4 sliding and
!>                                 \f$ \vect{u} \cdot \vect{n} = 0 \f$
!>                               - 5 smooth wall and
!>                                 \f$ \vect{u} \cdot \vect{n} = 0 \f$
!>                               - 6 rought wall and
!>                                 \f$ \vect{u} \cdot \vect{n} = 0 \f$
!>                               - 9 free inlet/outlet
!>                                 (input mass flux blocked to 0)
!> \param[in]     itrifb        indirection for boundary faces ordering
!> \param[in,out] itypfb        boundary face types
!> \param[out]    izfppp        boundary face zone number
!> \param[in]     dt            time step (per cell)
!> \param[in]     rtp, rtpa     calculated variables at cell centers
!> \param[in]                    (at current and previous time steps)
!> \param[in]     propce        physical properties at cell centers
!> \param[in,out] rcodcl        boundary condition values:
!>                               - rcodcl(1) value of the dirichlet
!>                               - rcodcl(2) value of the exterior exchange
!>                                 coefficient (infinite if no exchange)
!>                               - rcodcl(3) value flux density
!>                                 (negative if gain) in w/m2 or roughtness
!>                                 in m if icodcl=6
!>                                 -# for the velocity \f$ (\mu+\mu_T)
!>                                    \gradt \, \vect{u} \cdot \vect{n}  \f$
!>                                 -# for the pressure \f$ \Delta t
!>                                    \grad P \cdot \vect{n}  \f$
!>                                 -# for a scalar \f$ cp \left( K +
!>                                     \dfrac{K_T}{\sigma_T} \right)
!>                                     \grad T \cdot \vect{n} \f$
!_______________________________________________________________________________

subroutine cs_user_boundary_conditions &
 ( nvar   , nscal  ,                                              &
   icodcl , itrifb , itypfb , izfppp ,                            &
   dt     , rtp    , rtpa   , propce ,                            &
   rcodcl )

!===============================================================================

!===============================================================================
! Module files
!===============================================================================

use paramx
use numvar
use optcal
use cstphy
use cstnum
use entsor
use parall
use period
use ihmpre
use ppppar
use ppthch
use coincl
use cpincl
use ppincl
use ppcpfu
use atincl
use ctincl
use elincl
use cs_fuel_incl
use mesh
use field

!===============================================================================

implicit none

! Arguments

integer          nvar   , nscal

integer          icodcl(nfabor,nvarcl)
integer          itrifb(nfabor), itypfb(nfabor)
integer          izfppp(nfabor)

double precision dt(ncelet), rtp(ncelet,nflown:nvar), rtpa(ncelet,nflown:nvar)
double precision propce(ncelet,*)
double precision rcodcl(nfabor,nvarcl,3)

! Local variables

!< [loc_var_dec]
integer          ifac, ii, iel
integer          idim
integer          izone,iesp
integer          ilelt, nlelt

double precision uref2, d2s3
double precision rhomoy, dhy, ustar2
double precision xkent, xeent
double precision z1   , z2

integer, allocatable, dimension(:) :: lstelt
double precision, dimension(:), pointer :: brom
!< [loc_var_dec]

!===============================================================================

!===============================================================================
! Initialization
!===============================================================================

allocate(lstelt(nfabor))  ! temporary array for boundary faces selection

d2s3 = 2.d0/3.d0

!===============================================================================
! Assign boundary conditions to boundary faces here

! For each subset:
! - use selection criteria to filter boundary faces of a given subset
! - loop on faces from a subset
!   - set the boundary condition for each face
!===============================================================================

! --- For boundary faces of color 1 assign an inlet for all phases
!     ============================================================
!        and assign a cathode for "electric" variables.
!        =============================================
!
!< [example_1]
call field_get_val_s(ibrom, brom)
!===================

call getfbr('1', nlelt, lstelt)
!==========

do ilelt = 1, nlelt

  ifac = lstelt(ilelt)

  itypfb(ifac) = ientre

  ! Zone Number (from 1 to n)
  izone = 1

  ! Zone localization for a given face
  izfppp(ifac) = izone

  rcodcl(ifac,iu,1) = 0.d0
  rcodcl(ifac,iv,1) = 0.d0
  rcodcl(ifac,iw,1) = 0.d0

  ! Turbulence

  if (itytur.eq.2 .or. itytur.eq.3                  &
       .or. iturb.eq.50 .or. iturb.eq.60            &
       .or. iturb.eq.70) then

    uref2 = rcodcl(ifac,iu,1)**2                    &
           +rcodcl(ifac,iv,1)**2                    &
           +rcodcl(ifac,iw,1)**2
    uref2 = max(uref2,1.d-12)

    ! Turbulence example computed using equations valid for a pipe.

    ! We will be careful to specify a hydraulic diameter adapted
    ! to the current inlet.

    ! We will also be careful if necessary to use a more precise
    ! formula for the dynamic viscosity use in the calculation of
    ! the Reynolds number (especially if it is variable, it may be
    ! useful to take the law from 'usphyv'. Here, we use by default
    ! the 'viscl0" value.

    ! Regarding the density, we have acess to its value at boundary
    ! faces (romb) so this value is the one used here (specifically,
    ! it is consistent with the processing in 'usphyv', in case of
    ! variable density)

    ! Hydraulic diameter
    dhy     = 0.075d0

    ! Calculation of friction velocity squared (ustar2)
    ! and of k and epsilon at the inlet (xkent and xeent) using
    ! standard laws for a circular pipe
    ! (their initialization is not needed here but is good practice).

    rhomoy = brom(ifac)
    ustar2 = 0.d0
    xkent  = epzero
    xeent  = epzero

    call keendb                                            &
    !==========
     ( uref2, dhy, rhomoy, viscl0, cmu, xkappa,            &
       ustar2, xkent, xeent)

    if (itytur.eq.2) then

      rcodcl(ifac,ik,1)  = xkent
      rcodcl(ifac,iep,1) = xeent

    elseif (itytur.eq.3) then

      rcodcl(ifac,ir11,1) = d2s3*xkent
      rcodcl(ifac,ir22,1) = d2s3*xkent
      rcodcl(ifac,ir33,1) = d2s3*xkent
      rcodcl(ifac,ir12,1) = 0.d0
      rcodcl(ifac,ir13,1) = 0.d0
      rcodcl(ifac,ir23,1) = 0.d0
      rcodcl(ifac,iep,1)  = xeent

    elseif (iturb.eq.50) then

      rcodcl(ifac,ik,1)   = xkent
      rcodcl(ifac,iep,1)  = xeent
      rcodcl(ifac,iphi,1) = d2s3
      rcodcl(ifac,ifb,1)  = 0.d0

    elseif (iturb.eq.60) then

      rcodcl(ifac,ik,1)   = xkent
      rcodcl(ifac,iomg,1) = xeent/cmu/xkent

    elseif (iturb.eq.70) then

      rcodcl(ifac,inusa,1) = cmu*xkent**2/xeent

    endif

  endif

  ! --- Handle Scalars

  ! Enthalpy in J/kg (iscalt)
  ! On this example we impose the value of the enthalpy
  ! the arbitrary value of 1.d6 corresponds to a temperature of 2200 Kelvin
  ! for argon at atmospheric pressure (see dp_ELE)

  ii = iscalt
  icodcl(ifac,isca(ii))   = 1
  rcodcl(ifac,isca(ii),1) = 1.d6

  !  Electric potential  (ipotr)
  ! (could corresponds also to the real part of the electrical potential if
  ! Joule Effect by direct conduction)

  ! In the Cathode example (electric arc applications),
  ! we impose a constant value of the electrical potential which is zero,
  ! assuming that the potential is equal to "ipotr + an arbitrary constant"
  ! (What is important for electric arc is the difference between anode and
  ! cathode potentials)

  ii = ipotr
  icodcl(ifac,isca(ii))   = 1
  rcodcl(ifac,isca(ii),1) = 0.d0

  ! Mass fraction of the (n-1) gas mixture components

  if (ngazg .gt. 1) then
    do iesp=1,ngazg-1
      ii = iycoel(iesp)
      icodcl(ifac,isca(ii))   = 1
      rcodcl(ifac,isca(ii),1) = 0.d0
    enddo
  endif

  ! Specific model for Joule effect by direct conduction:
  ! Imaginary part of the potentiel (ipoti) is imposed to zero

  if (ippmod(ieljou).ge. 2) then
    ii = ipoti
    icodcl(ifac,isca(ii))   = 1
    rcodcl(ifac,isca(ii),1) = 0.d0
  endif

  ! Specific model for Electric arc:
  ! Vector Potential: Zero flux by default beacuse we don't a lot about
  ! vector potential (what we know, is that A is equal to zero at the infinite)

  ! All the boundary conditions for A are zero flux, except on some chosen faces
  ! where we need to impose a value in order to have a stable calculation
  ! (well defined problem)
  ! These faces are chosen where we are sure that the electrical current density
  ! remains very low generally far from the center of the electric arc and from
  ! the electrodes (see above)

  if (ippmod(ielarc).ge.2) then
    do idim= 1,ndimve
      ii = ipotva(idim)
      icodcl(ifac,isca(ii))   = 3
      rcodcl(ifac,isca(ii),3) = 0.d0
    enddo
  endif

enddo
!< [example_1]

! --- For boundary faces of color 5 assign an free outlet for all phases
!     ==================================================================
!        and example of electrode for Joule Effect by direct conduction.
!        ==============================================================
!
!< [example_2]
call getfbr('5', nlelt, lstelt)
!==========

do ilelt = 1, nlelt

  ifac = lstelt(ilelt)

  itypfb(ifac)   = isolib

  ! Zone Number (from 1 to n)
  izone = 2

  ! Zone location for a given face

  izfppp(ifac) = izone

  ! --- Handle Scalars

  ! Enthalpy in J/kg  (By default zero flux with ISOLIB)
  !    Nothing to do

  ! Mass fraction of the (n-1) gas mixture components
  ! (Zero flux by defaut with ISOLIB)
  !    Nothing to do

  ! Specific model for Joule Effect by direct conduction:

  ! If you want to make a simulation with an imposed Power PUISIM
  ! (you want to get PUISIM imposed in useli1 and PUISIM = Amp x Volt)
  ! you need to impose IELCOR=1 in useli1
  ! The boundary conditions will be scaled by COEJOU coefficient
  ! for example the electrical potential will be multiplied bu COEJOU
  ! (both real and imaginary part of the electrical potential if needed)

  ! COEJOU is automatically defined in order that the calculated dissipated power
  ! by Joule effect (both real and imaginary part if needed) is equal to PUISIM

  ! At the beginning of the calculation, COEJOU ie equal to 1;
  ! COEJOU is writing and reading in the result files.

  ! If you don't want to calculate with by scaling,
  ! you can impose directly the value.

  if (ippmod(ieljou).ge. 1) then
    ii = ipotr
    icodcl(ifac,isca(ii))   = 1
    if (ielcor.eq.1) then
      rcodcl(ifac,isca(ii),1) = 500.d0*coejou
    else
      rcodcl(ifac,isca(ii),1) = 500.d0
    endif
  endif

  if (ippmod(ieljou).ge. 2) then
    ii = ipoti
    icodcl(ifac,isca(ii))   = 1
    if (ielcor.eq.1) then
      rcodcl(ifac,isca(ii),1) = sqrt(3.d0)*500.d0*coejou
    else
      rcodcl(ifac,isca(ii),1) = sqrt(3.d0)*500.d0
    endif
  endif

enddo
!< [example_2]

! --- For boundary faces of color 2 assign a free outlet for all phases
!     =================================================================
!        and example of anode for electric arc.
!        =====================================
!
!< [example_3]
call getfbr('2', nlelt, lstelt)
!==========

do ilelt = 1, nlelt

  ifac = lstelt(ilelt)

  itypfb(ifac)   = isolib

  ! Zone number (from 1 to n)
  izone = 3

  ! Zone localization for a given face
  izfppp(ifac) = izone

  ! --- Handle scalars

  ! Enthalpy in J/kg  (Zero flux by default with ISOLIB)
  !    Nothing to do

  ! Real component of the electrical potential

  ! For electric arc model,
  ! ======================
  ! *  we generally calculate the "electric variables" assuming that the total
  !    intensity of the electrical current is imposed (COUIMP is the value of
  !    the imposed total current).

  !    In that case, you need to impose IELCOR=1 in useli1
  !    The "electrical variables" will be scaled by COEPOT coefficient :
  !    for example the electrical potential will be multiplied by COEPOT,
  !    Joule effect will be multipied by COEPOT * COEPOT and so on (see uselrc.f90)

  !    COEJOU is defined in uselrc.fr : different possibilities are described in
  !    uselrc.f90, depending on the different physics you want to simulate
  !    (scaling from current, from power, special model for restriking ...)

  !    The variable DPOT is defined: it corresponds to the electrical potential
  !    difference between the electrodes (Anode potential - cathode Potential).
  !    DPOT is calculated in uselrc.f90. DPOT is saved at each time step, and
  !    for a following calculation

  !    DPOT is the value of the boundary condition on anode assuming that
  !    the cathode potential is equel to zero.

  ! *  It is also possible to fix the value of the potential on the anode.
  !    (for example, 1000 Volts).

  ii = ipotr
  icodcl(ifac,isca(ii))   = 1

  if (ippmod(ielarc).ge.1 .and. ielcor .eq.1) then
    rcodcl(ifac,isca(ii),1) = dpot
  else
    rcodcl(ifac,isca(ii),1) = 1000.d0
  endif

  ! Mass fraction of the (n-1) gas mixture components
  !  zero flux by default with ISOLIB
  !  nothing to do

  ! vector Potential
  !  zero flux by default with ISOLIB
  !  nothing to do

enddo
!< [example_3]

! --- For boundary faces of color 3 assign a wall for all phases
!     ==========================================================
!        and example of potential vector Dirichlet condition
!        ===================================================

!< [example_4]
call getfbr('3', nlelt, lstelt)
!==========

do ilelt = 1, nlelt

  ifac = lstelt(ilelt)

  itypfb(ifac)   = iparoi

  ! Zone number (from 1 to n)
  izone = 4

  ! Zone localization for a given face
  izfppp(ifac) = izone

  ! Wall: zero flow (zero flux for pressure)
  !       friction for velocities (+ turbulent variables)
  !       zero flux for scalars

  ! --- Handle scalars
  !  Enthalpy in J/kg  (Zero flux by default)
  !     Nothing to do

  ! Real component of the electrical potential
  !    Zero flux by default
  !    Nothing to do

  ! Specific model for Electric arc :
  ! ================================

  ! Vector potential  A (Ax, Ay, Az)

  ! Zero flux by default because we don't a lot about vector potential
  ! (what we know, is that A is equal to zero at the infinite)

  ! All the boundary conditions for A are zero flux, except on some chosen faces
  ! where we need to impose a value in order to have a stable calculation
  ! These faces are chosen where we are sure that the electrical current density
  ! remains very low generally far from the center of the electric arc and from
  ! the electrodes:

  ! On the following example, we choose to impose a "dirichlet" value for the
  ! 3 components of A on a small zone of the boundary located near the vertical
  ! free outlet of the computation domain.

  ! In this example, the electric arc is at the center of the computational domain,
  ! located on z axis (near x = 0 and y = 0).
  ! The x (1st) and y (the 3rd) coordinates are contained between
  ! -2.5 cm nd 2.5 cm:

  !    Ax(t, x,y,z) = Ax(t-dt, x=2.5cm, y=2.5cm, z)
  !    Ay(t, x,y,z) = Ay(t-dt, x=2.5cm, y=2.5cm, z)
  !    Az(t, x,y,z) = Az(t-dt, x=2.5cm, y=2.5cm, z)

  if (ippmod(ielarc).ge.2) then
    if (cdgfbo(1,ifac) .le.  2.249d-2  .or.                      &
        cdgfbo(1,ifac) .ge.  2.249d-2  .or.                      &
        cdgfbo(3,ifac) .le. -2.249d-2  .or.                      &
        cdgfbo(3,ifac) .ge.  2.249d-2      ) then
      iel = ifabor(ifac)
      do idim = 1, ndimve
        ii = ipotva(idim)
        icodcl(ifac,isca(ii))   = 1
        rcodcl(ifac,isca(ii),1) = rtpa(iel,isca(ii))
      enddo
    endif
  endif

enddo
!< [example_4]

! --- For boundary faces of color 51 assign a wall
!     ============================================
!        and restriking model for electric arc (anode boundaray condition)
!        =================================================================

!< [example_5]
call getfbr('51', nlelt, lstelt)
!==========

do ilelt = 1, nlelt

  ifac = lstelt(ilelt)

  itypfb(ifac)   = iparoi

  ! Zone number (from 1 to n)
  izone = 5

  ! Zone localization for a given face
  izfppp(ifac) = izone

  ! ---- Enthalpy (J/kg) :
  !      imposed heat transfer coefficient

  ii=iscalt
  icodcl(ifac,isca(ii))   = 1
  rcodcl(ifac,isca(ii),1) = 2.d4
  rcodcl(ifac,isca(ii),2) = 1.d5

  ! Real electrical potential: anode boundary condition;
  ! dpot calculated in uselrc.f

  ii = ipotr
  icodcl(ifac,isca(ii))   = 1

  if (ippmod(ielarc).ge.1 .and. ielcor .eq.1) then
    rcodcl(ifac,isca(ii),1) = dpot
  else
    rcodcl(ifac,isca(ii),1) = 100.d0
  endif

  ! Restriking modeling:
  ! ===================
  !    example to fit depending on the case, the geometry etc...
  !     and also in agreement with uselrc.fr

  if (ippmod(ielarc).ge.1 .and. ielcor .eq.1) then
    if (iclaq.eq.1 .and. ntcabs.le.ntdcla+30) then

      z1 = zclaq - 2.d-4
      if (z1.le.0.d0) z1 = 0.d0
      z2 = zclaq + 2.d-4
      if (z2.ge.2.d-2) z2 = 2.d-2

      if (cdgfbo(3,ifac).ge.z1 .and. cdgfbo(3,ifac).le.z2) then
        icodcl(ifac,isca(ii))   = 1
        rcodcl(ifac,isca(ii),1) = dpot
      else
        icodcl(ifac,isca(ii))   = 3
        rcodcl(ifac,isca(ii),3) = 0.d0
      endif
    endif
  endif

  ! Vector potential : Zero flux

  if (ippmod(ielarc).ge.2) then
    do idim= 1,ndimve
      ii = ipotva(idim)
      icodcl(ifac,isca(ii))   = 3
      rcodcl(ifac,isca(ii),3) = 0.d0
    enddo
  endif

enddo
!< [example_5]

! --- For boundary faces of color 4 assign a symetry
!     ==============================================

!< [example_6]
call getfbr('4', nlelt, lstelt)
!==========

do ilelt = 1, nlelt

  ifac = lstelt(ilelt)

  ! Symmetries

  itypfb(ifac)   = isymet

  ! Zone number (from 1 to n)
  izone = 6

  ! Zone localization for a given face
  izfppp(ifac) = izone

  ! For all scalars, by default a zero flux condition is assumed
  ! (for potentials also)

  ! In Joule effect direct conduction,
  ! we can use an anti-symetry condition for the imaginary component of the
  ! electrical potential depending on the electrode configuration:

  if (ippmod(ieljou).ge. 2) then
    ii = ipoti
    icodcl(ifac,isca(ii))   = 1
    rcodcl(ifac,isca(ii),1) = 0.d0
  endif

enddo
!< [example_6]

!--------
! Formats
!--------

!----
! End
!----

deallocate(lstelt)  ! temporary array for boundary faces selection

return
end subroutine cs_user_boundary_conditions
