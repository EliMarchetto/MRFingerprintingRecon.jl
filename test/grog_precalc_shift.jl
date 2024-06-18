using BenchmarkTools
using MRFingerprintingRecon
using ImagePhantoms
using LinearAlgebra
using IterativeSolvers
using FFTW
using NFFT
using SplitApplyCombine
using Test

##
T  = Float32
Nx = 32
Nr = 2Nx
Nt = 100
Ncoil = 9
Nrep = 3
Nd = 2

## Create trajectory
trj = MRFingerprintingRecon.traj_2d_radial_goldenratio(Nr, 1, Nt; N=1)
trj = [trj[i][1:Nd,:] for i ∈ eachindex(trj)] # only 2D traj, here

## Create phantom geometry
x = shepp_logan(Nx)

## Simulate coil sensitivity maps
cmaps = ones(Complex{T}, Nx, Nx, Ncoil)
cmaps[:,:,1] .= phantom(1:Nx, 1:Nx, [gauss2((Nx÷8,  Nx÷8),  (Nx÷1.5,Nx÷1.5))], 2)
cmaps[:,:,2] .= phantom(1:Nx, 1:Nx, [gauss2((Nx÷8,  Nx÷2),  (Nx÷1.5,Nx÷1.5))], 2)
cmaps[:,:,3] .= phantom(1:Nx, 1:Nx, [gauss2((Nx÷8,  7Nx÷8), (Nx÷1.5,Nx÷1.5))], 2)
cmaps[:,:,4] .= phantom(1:Nx, 1:Nx, [gauss2((Nx÷2,  Nx÷8),  (Nx÷1.5,Nx÷1.5))], 2)
cmaps[:,:,5] .= phantom(1:Nx, 1:Nx, [gauss2((Nx÷2,  Nx÷2),  (Nx÷1.5,Nx÷1.5))], 2)
cmaps[:,:,6] .= phantom(1:Nx, 1:Nx, [gauss2((Nx÷2,  7Nx÷8), (Nx÷1.5,Nx÷1.5))], 2)
cmaps[:,:,7] .= phantom(1:Nx, 1:Nx, [gauss2((7Nx÷8, Nx÷8),  (Nx÷1.5,Nx÷1.5))], 2)
cmaps[:,:,8] .= phantom(1:Nx, 1:Nx, [gauss2((7Nx÷8, Nx÷2),  (Nx÷1.5,Nx÷1.5))], 2)
cmaps[:,:,9] .= phantom(1:Nx, 1:Nx, [gauss2((7Nx÷8, 7Nx÷8), (Nx÷1.5,Nx÷1.5))], 2)

for i ∈ CartesianIndices(@view cmaps[:,:,1])
    cmaps[i,:] ./= norm(cmaps[i,:])
end

cmaps = [cmaps[:,:,ic] for ic=1:Ncoil]


## Simulate data
data = Array{Complex{T}}(undef, size(trj[1], 2), Nt, Ncoil)
nfftplan = plan_nfft(trj[1], (Nx,Nx))
xcoil = copy(x)
for icoil ∈ 1:Ncoil
    xcoil .= x
    xcoil .*= cmaps[icoil]
    for it ∈ axes(data,2)
        nodes!(nfftplan, trj[it])
        @views mul!(data[:,it,icoil], nfftplan, xcoil)
    end
end

# Create repeating pattern
data2 = repeat(deepcopy(data), outer = [1, 1, 1, Nrep])
data2 = reshape(permutedims(data2, (1,2,4,3)),Nr, :, Ncoil)

data2 = [data2[:,it,:] for it ∈ axes(data2,2)]
data = [data[:,it,:] for it=1:Nt]

## #####################################
# Test Calibration of GROG kernel
########################################

lnG = MRFingerprintingRecon.grog_calib(data, trj, Nr)
lnG2 = MRFingerprintingRecon.grog_calib(data2, trj, Nr)

@test lnG ≈ lnG2 rtol = 1e-6

## #####################################
# Test Gridding with GROG kernel
########################################
trj1 =  deepcopy(trj)

# Gridding of each sample with non repeating trajectory (Reference)
MRFingerprintingRecon.grog_gridding!(data, trj1, lnG, Nr, (Nx,Nx))

# Exploit Precalculated Shifts
MRFingerprintingRecon.grog_gridding!(data2, trj, lnG2, Nr, (Nx,Nx))

# Compare gridding with and without repeating pattern
for it = 1:Nt
    @test data[it] ≈ data2[it][:,:] rtol = 1e-6
    @test data[it] ≈ data2[it + 200][:,:] rtol = 1e-6
end

## #####################################
# Test Gridded Reconstruction with and without Repeating Pattern
########################################

U = ones(ComplexF32, length(data), 1)

# Reconstruction without repeating pattern
A_grog = FFTNormalOp((Nx,Nx), trj, U; cmaps)
x1 = calculateBackProjection_gridded(data, trj, U, cmaps)
xg1 = cg(A_grog, vec(x1), maxiter=20)
xg1 = reshape(xg1, Nx, Nx)

# Reconstruction with repeating pattern
U2 = repeat(U, outer=[Nrep]) # For joint subspace reconstruction
A_grog = FFTNormalOp((Nx,Nx), trj, U2; cmaps)
x2 = calculateBackProjection_gridded(data2, trj, U2, cmaps)
xg2 = cg(A_grog, vec(x2), maxiter=20)
xg2 = reshape(xg2, Nx, Nx)

@test xg1 ≈ xg2 rtol = 5e-3

# using Plots
# heatmap(abs.(cat(reshape(xg1, Nx, :), reshape(xg2, Nx, :), dims=1)), clim=(0.75, 1.25))