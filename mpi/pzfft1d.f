C
C     FFTE: A FAST FOURIER TRANSFORM PACKAGE
C
C     (C) COPYRIGHT SOFTWARE, 2000-2004, 2008-2014, ALL RIGHTS RESERVED
C                BY
C         DAISUKE TAKAHASHI
C         FACULTY OF ENGINEERING, INFORMATION AND SYSTEMS
C         UNIVERSITY OF TSUKUBA
C         1-1-1 TENNODAI, TSUKUBA, IBARAKI 305-8573, JAPAN
C         E-MAIL: daisuke@cs.tsukuba.ac.jp
C
C
C     PARALLEL 1-D COMPLEX FFT ROUTINE
C
C     FORTRAN90 + MPI SOURCE PROGRAM
C
C     CALL PZFFT1D(A,B,W,N,ICOMM,ME,NPU,IOPT)
C
C     W(N/NPU) IS COEFFICIENT VECTOR (COMPLEX*16)
C     N IS THE LENGTH OF THE TRANSFORMS (INTEGER*8)
C       -----------------------------------
C         N = (2**IP) * (3**IQ) * (5**IR)
C       -----------------------------------
C     ICOMM IS THE COMMUNICATOR (INTEGER*4)
C     ME IS THE RANK (INTEGER*4)
C     NPU IS THE NUMBER OF PROCESSORS (INTEGER*4)
C     IOPT = 0 FOR INITIALIZING THE COEFFICIENTS (INTEGER*4)
C     IOPT = -1 FOR FORWARD TRANSFORM WHERE
C              A(N/NPU) IS COMPLEX INPUT VECTOR (COMPLEX*16)
C!HPF$ DISTRIBUTE A(BLOCK)
C              B(N/NPU) IS COMPLEX OUTPUT VECTOR (COMPLEX*16)
C!HPF$ DISTRIBUTE B(BLOCK)
C     IOPT = +1 FOR INVERSE TRANSFORM WHERE
C              A(N/NPU) IS COMPLEX INPUT VECTOR (COMPLEX*16)
C!HPF$ DISTRIBUTE A(BLOCK)
C              B(N/NPU) IS COMPLEX OUTPUT VECTOR (COMPLEX*16)
C!HPF$ DISTRIBUTE B(BLOCK)
C
C     WRITTEN BY DAISUKE TAKAHASHI
C
      SUBROUTINE PZFFT1D(A,B,W,N,ICOMM,ME,NPU,IOPT)
      IMPLICIT REAL*8 (A-H,O-Z)
      INCLUDE 'mpif.h'
      INCLUDE 'param.h'
      COMPLEX*16 A(*),B(*),W(*)
      COMPLEX*16 C(:)
      ALLOCATABLE :: C
!DIR$ ATTRIBUTES ALIGN : 16 :: C
      INTEGER*8 N
      INTEGER*4 TID
!$    INTEGER*4 OMP_GET_NUM_THREADS,OMP_GET_THREAD_NUM
C
      NN=N/NPU
C
      CALL PGETNXNY(N,NX,NY,NPU)
C
      IF (IOPT .EQ. 0) THEN
        CALL PSETTBL(W,NX,NY,ME,NPU)
        RETURN
      END IF
C
      IF (IOPT .EQ. 1) THEN
!$OMP PARALLEL DO
!DIR$ VECTOR ALIGNED
        DO 10 I=1,NN
          A(I)=DCONJG(A(I))
   10   CONTINUE
      END IF
C
      NTHREADS=1
      TID=0
!$OMP PARALLEL PRIVATE(TID)
!$OMP SINGLE
!$    NTHREADS=OMP_GET_NUM_THREADS()
!$OMP END SINGLE
!$    TID=OMP_GET_THREAD_NUM()
      IF (NN .LT. (MAX0(NX,NY)*2+NP)*NTHREADS) THEN
!$OMP SINGLE
        ALLOCATE(C((MAX0(NX,NY)*2+NP)*NTHREADS))
!$OMP END SINGLE
        CALL PZFFT1D0(A,A,A,A,B,B,B,B,C(TID*(NX*2+NP)+1),
     1                C(TID*(NY*2+NP)+1),W,NX,NY,ICOMM,NPU)
!$OMP SINGLE
        DEALLOCATE(C)
!$OMP END SINGLE
      ELSE
        CALL PZFFT1D0(A,A,A,A,B,B,B,B,B(TID*(NX*2+NP)+1),
     1                A(TID*(NY*2+NP)+1),W,NX,NY,ICOMM,NPU)
      END IF
!$OMP END PARALLEL
C
      IF (IOPT .EQ. 1) THEN
        DN=1.0D0/DBLE(N)
!$OMP PARALLEL DO
!DIR$ VECTOR ALIGNED
        DO 20 I=1,NN
          B(I)=DCONJG(B(I))*DN
   20   CONTINUE
      END IF
      RETURN
      END
      SUBROUTINE PZFFT1D0(A,AXPY,AXY,AYXP,B,BXYP,BYPX,BYX,CX,CY,W,NX,NY,
     1                    ICOMM,NPU)
      IMPLICIT REAL*8 (A-H,O-Z)
      INCLUDE 'mpif.h'
      INCLUDE 'param.h'
      COMPLEX*16 A(NX,*),AXPY(NX/NPU,NPU,*),AXY(NX/NPU,*),
     1           AYXP(NY/NPU,NX/NPU,*)
      COMPLEX*16 B(NY,*),BXYP(NX/NPU,NY/NPU,*),BYPX(NY/NPU,NPU,*),
     1           BYX(NY/NPU,*)
      COMPLEX*16 CX(*),CY(*)
      COMPLEX*16 W(NY/NPU,NPU,*)
C
      NNX=NX/NPU
      NNY=NY/NPU
      NN=NX*NNY
C
!$OMP DO
      DO 30 J=1,NNY
        DO 20 K=1,NPU
!DIR$ VECTOR ALIGNED
          DO 10 I=1,NNX
            BXYP(I,J,K)=AXPY(I,K,J)
   10     CONTINUE
   20   CONTINUE
   30 CONTINUE
!$OMP BARRIER
!$OMP MASTER
      CALL MPI_ALLTOALL(BXYP,NN/NPU,MPI_DOUBLE_COMPLEX,AXY,NN/NPU,
     1                  MPI_DOUBLE_COMPLEX,ICOMM,IERR)
!$OMP END MASTER
!$OMP BARRIER
      DO 70 II=1,NNX,NBLK
!$OMP DO
        DO 60 JJ=1,NY,NBLK
          DO 50 I=II,MIN0(II+NBLK-1,NNX)
!DIR$ VECTOR ALIGNED
            DO 40 J=JJ,MIN0(JJ+NBLK-1,NY)
              B(J,I)=AXY(I,J)
   40       CONTINUE
   50     CONTINUE
   60   CONTINUE
   70 CONTINUE
      CALL ZFFT1D(B,NY,0,CY)
!$OMP DO
      DO 80 I=1,NNX
        CALL ZFFT1D(B(1,I),NY,-1,CY)
   80 CONTINUE
!$OMP DO
      DO 110 I=1,NNX
        DO 100 K=1,NPU
!DIR$ VECTOR ALIGNED
          DO 90 J=1,NNY
            AYXP(J,I,K)=BYPX(J,K,I)*W(J,K,I)
   90     CONTINUE
  100   CONTINUE
  110 CONTINUE
!$OMP BARRIER
!$OMP MASTER
      CALL MPI_ALLTOALL(AYXP,NN/NPU,MPI_DOUBLE_COMPLEX,BYX,NN/NPU,
     1                  MPI_DOUBLE_COMPLEX,ICOMM,IERR)
!$OMP END MASTER
!$OMP BARRIER
      DO 150 JJ=1,NNY,NBLK
!$OMP DO
        DO 140 II=1,NX,NBLK
          DO 130 J=JJ,MIN0(JJ+NBLK-1,NNY)
!DIR$ VECTOR ALIGNED
            DO 120 I=II,MIN0(II+NBLK-1,NX)
              A(I,J)=BYX(J,I)
  120       CONTINUE
  130     CONTINUE
  140   CONTINUE
  150 CONTINUE
      CALL ZFFT1D(A,NX,0,CX)
!$OMP DO
      DO 160 J=1,NNY
        CALL ZFFT1D(A(1,J),NX,-1,CX)
  160 CONTINUE
!$OMP DO
      DO 190 J=1,NNY
        DO 180 K=1,NPU
!DIR$ VECTOR ALIGNED
          DO 170 I=1,NNX
            BXYP(I,J,K)=AXPY(I,K,J)
  170     CONTINUE
  180   CONTINUE
  190 CONTINUE
!$OMP BARRIER
!$OMP MASTER
      CALL MPI_ALLTOALL(BXYP,NN/NPU,MPI_DOUBLE_COMPLEX,AXY,NN/NPU,
     1                  MPI_DOUBLE_COMPLEX,ICOMM,IERR)
!$OMP END MASTER
!$OMP BARRIER
      DO 230 II=1,NNX,NBLK
!$OMP DO
        DO 220 JJ=1,NY,NBLK
          DO 210 I=II,MIN0(II+NBLK-1,NNX)
!DIR$ VECTOR ALIGNED
            DO 200 J=JJ,MIN0(JJ+NBLK-1,NY)
              B(J,I)=AXY(I,J)
  200       CONTINUE
  210     CONTINUE
  220   CONTINUE
  230 CONTINUE
      RETURN
      END
      SUBROUTINE PSETTBL(W,NX,NY,ME,NPU)
      IMPLICIT REAL*8 (A-H,O-Z)
      COMPLEX*16 W(NY,*)
C
      PI2=8.0D0*DATAN(1.0D0)
      PX=-PI2/(DBLE(NX)*DBLE(NY))
!$OMP PARALLEL DO PRIVATE(TEMP)
      DO 20 I=1,NX/NPU
!DIR$ VECTOR ALIGNED
        DO 10 J=1,NY
          TEMP=PX*DBLE(J-1)*(DBLE(I-1)+DBLE(ME)*DBLE(NX/NPU))
          W(J,I)=DCMPLX(DCOS(TEMP),DSIN(TEMP))
   10   CONTINUE
   20 CONTINUE
      RETURN
      END
