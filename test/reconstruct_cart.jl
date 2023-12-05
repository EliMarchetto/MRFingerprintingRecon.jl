using BenchmarkTools
using MRFingerprintingRecon
using ImagePhantoms
using LinearAlgebra
using IterativeSolvers
using FFTW
using Test

## set parameters
T  = Float32
Nx = 64
Nc = 4
Nt = 100
Ncyc = 100

## create test image
x = zeros(Complex{T}, Nx, Nx, Nc)
x[:,:,1] = transpose(shepp_logan(Nx))
x[1:end÷2,:,1] .*= exp(1im * π/3)

## set up basis functions
U = randn(Complex{T}, Nt, Nc)
U,_,_ = svd(U)

## simulate data
data = Array{Complex{T}}(undef, Nx, Nx, Nt)
xr = reshape(x, :, Nc)
fftplan = plan_fft(@view x[:,:,1])
for it ∈ axes(data,3)
    xt = reshape(xr * U[it,:], Nx, Nx)
    @views mul!(data[:,:,it], fftplan, xt)
end

## construct forward operator
A = FFTNormalOpBasisFuncLO((Nx,Nx), ones(Int16, Nx, Nx, Nt), U; verbose = true)

## test forward operator
for i ∈ CartesianIndices((Nx, Nx))
    @test A.prod!.A.Λ[:,:,i]' ≈ A.prod!.A.Λ[:,:,i] rtol = eps(T)
end

## reconstruct
xr = similar(vec(x))
xr .= 0
cg!(xr, A, vec(x), maxiter=20)
xr = reshape(xr, Nx, Nx, Nc)

##
@test xr ≈ x rtol = 1e-5

##
# using Plots
# plot(
#     heatmap(abs.(cat(x[:,:,1], xr[:,:,1], dims=2)), aspect_ratio=1),
#     heatmap(angle.(cat(x[:,:,1], xr[:,:,1], dims=2)), aspect_ratio=1),
#     size=(800,800), layout=(2,1)
# )