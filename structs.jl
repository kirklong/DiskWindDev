#!/usr/bin/env julia
using Random

mutable struct ring{V,F} #NOTE: should change this to be non-mutable (small ~10% performance gain) but have to make only Array fields allowed so that the fields themselves can be mutated (Float64 cannot be changed after initialization, needed for raytracing)
    """structure to hold parameters of model ring
    attributes:
        r: distance from central mass (in terms of rₛ) Union{Vector{Float64},Float64
            - can be Float64 for constant r across ϕ or single point at (r,ϕ), otherwise it is a Vector{Float64} of distances corresponding to azimuthal angles ϕ
            - user can (optionally) supply a function to calculate r from other parameters (see constructor) that returns a Vector{Float64} or Float64
        i: inclination angle (rad) {Float64}
            - must be between 0 and π/2, with 0 being face-on and π/2 being edge-on
        rot: rotation of system plane about z axis (rad) {Float64}
        θₒ: opening angle (rad) of ring {Float64}
            - should be between 0 and π/2
            - optional, defaults to 0
        v: line of sight velocity {Union{Vector{Float64},Float64}}
            - Float64 for a single angle, otherwise a Vector{Float64} of velocities corresponding to azimuthal angles ϕ
            - user can (optionally) supply a function to calculate v from other parameters (see constructor) that returns a Vector{Float64}
        I: intensity {Union{Vector{Float64},Float64,Matrix{Float64}}
            - Float64 for a single angle, otherwise a Vector{Float64} of intensities corresponding to azimuthal angles ϕ
            - user can (optionally) supply a function to calculate I from other parameters (see constructor) that returns a Vector{Float64}
        ϕ: azimuthal angle (rad) {Union{Vector{Float64},Float64}}
            - Float64 for a single point, otherwise a Vector{Float64} of azimuthal angles
        ϕ₀ (optional): azimuthal angle of system before rotation (rad) {Union{Vector{Float64},Float64}}
            - Float64 for a single point, otherwise a Vector{Float64} of azimuthal angles
            - defaults to 0.0 if not provided or if rot is 0.0 (if no rotation ϕ = ϕ₀)
        ΔA: projected area of ring in image (used in calculating profiles) {Union{Vector{Float64},Float64}}
            - Float64 for a single point, otherwise a Vector{Float64} of projected areas corresponding to azimuthal angles ϕ
            - defaults to 1.0 if not provided
    
    constructor:
        ring(;r, i, rot, θₒ, v, I, ϕ, ϕ₀, kwargs...)
        r: Float64, Vector{Float64} or Function
            - if function, must return a Vector{Float64} or Float64 corresponding to ϕ
        i: Float64
            - must be between 0 and π/2
        rot: Float64
            - optional (defaults to 0.0)
            - must be between 0 and 2π (or -π to π)
            - describes 3D rotation about z axis of ring plane
        θₒ: Float64
            - optional (defaults to 0.0)
            - must be between 0 and π/2
            - opening angle of ring (i.e. thin disk has opening angle near 0.0 and spherical shell has opening angles distributed between 0 and π/2)
        v: Float64, Vector{Float64} or Function
            - if function, must return a Vector{Float64} corresponding to ϕ
        I: Float64, Vector{Float64}, Matrix{Float64}, or Function
            - if function, must return a Vector{Float64} corresponding to ϕ for each r (if r is a Vector{Float64} must return a Matrix{Float64} of intensities for each r)
        ϕ: Float64 or Vector{Float64}
            - must be between 0 and 2π
            - if Float64, r, v, and I must be Float64 (or functions that return Float64)
        ϕ₀: Float64 or Vector{Float64}
            - optional (defaults to 0.0)
        ΔA: Float64 or Vector{Float64}
            - projected area of ring in image (used in calculating profiles)
            - i.e. for log-spherical ring ΔA = r^2*Δr*Δϕ, for linear-spherical ring ΔA = r*Δr*Δϕ, for cloud ΔA could be size of cloud (note here r would be the image r not the physical r)
            - defaults to 1.0 if not provided
        reflect: Bool
            - optional (defaults to false)
            - if true, cloud is reflected across disk mid-plane to front
        τ: Float64 or Vector{Float64} or Function
            - optional (defaults to 0.0)
            - optical depth(s) of ring -- after passing through this ring, the total optical depth is increased by τ
        η: Float64 or Vector{Float64} or Function
            - optional (defaults to 1.0)
            - response parameter for ring -- affects weighting in delay profile/transfer functions
        kwargs: contain extra keyword arguments for v, I, r, and/or τ if they are functions (see examples)
    """

    r::Union{V,F,Function}
    i::F
    rot::F
    θₒ::F
    v::Union{V,F,Function}
    I::Union{V,F,Matrix{F},Function}
    ϕ::Union{V,F}
    ϕ₀::Union{V,F}
    ΔA::Union{V,F}
    reflect::Bool
    τ::Union{V,F,Function}
    η::Union{V,F,Function}

    function ring(;kwargs...) #could re-write this to use multiple dispatch? i.e. ring(;r::Float64, i::Float64, e::Float64, v::Float64, I::Float64, ϕ::Float64) etc.
        """
        constructor for ring struct -- takes in kwargs (detailed above) and returns a ring object (detailed above) while checking for errors
        """
        r = nothing; i = nothing; v = nothing; I = nothing; ϕ = nothing; ΔA = 1.0; rot = 0.0; θₒ = 0.0; ϕ₀ = 0.0; reflect = false; τ = 0.0; η = 1.0
        try; r = kwargs[:r]; catch; error("r must be provided as kwarg"); end
        try; i = kwargs[:i]; catch; error("i must be provided as kwarg"); end
        try; v = kwargs[:v]; catch; error("v must be provided as kwarg"); end
        try; I = kwargs[:I]; catch; error("I must be provided as kwarg"); end
        try; ϕ = kwargs[:ϕ]; catch; error("ϕ must be provided as kwarg"); end
        try; ΔA = kwargs[:ΔA]; catch; error("ΔA not provided, defaulting to 1.0"); end
        try; rot = kwargs[:rot]; catch; println("rot not provided: defaulting to 0.0"); end
        try; θₒ = kwargs[:θₒ]; catch; println("θₒ not provided: defaulting to 0.0"); end
        try; ϕ₀ = kwargs[:ϕ₀]; catch; println("ϕ₀ not provided: defaulting to 0.0"); end
        try; reflect = kwargs[:reflect]; catch; println("reflect not provided: defaulting to false"); end
        try; τ = kwargs[:τ]; catch; println("τ not provided: defaulting to 0.0"); end
        try; η = kwargs[:η]; catch; println("η not provided: defaulting to 1.0"); end
        kwargs = values(kwargs)
        
        @assert typeof(reflect) == Bool "reflect must be Bool, got $(typeof(reflect))"
        @assert typeof(i) == Float64 "i must be Float64, got $(typeof(i))"
        @assert (i >= -π/2) && (i <= π/2) "i must be between -π/2 and π/2, got $i"
        i = -i #flip i to match convention of bottom of disk being tilted "towards" observer, relic of how rotation matrix was implemented.
        @assert (typeof(rot) == Float64) "rot must be Float64, got $(typeof(rot))"
        @assert (typeof(θₒ) == Float64) "θₒ must be Float64, got $(typeof(θₒ))"
        @assert (θₒ >= 0) && (θₒ <= π/2) "θₒ must be between 0 and π/2, got $θₒ"
        @assert (typeof(ΔA) == Float64) || (typeof(ΔA) == Vector{Float64}) "ΔA must be Float64 or Vector{Float64}, got $(typeof(ΔA))"
        if typeof(ΔA) == Vector{Float64}
            @assert length(ΔA) == length(ϕ) "ΔA must be the same length as ϕ"
        end
        @assert (typeof(r) == Vector{Float64}) || (typeof(r) == Float64) || (isa(r,Function)) "r must be Float64, Vector{Float64} or Function, got $(typeof(r))"   
        if isa(r,Function)
            try; r = r(;kwargs...); catch; error("error in function r -- check kwargs"); end
            @assert length(r) == length(ϕ) "r must return a vector of the same length as ϕ"
        elseif typeof(r) == Vector{Float64}
            @assert length(r) == length(ϕ) "r must be the same length as ϕ"
        end

        @assert (typeof(η) == Vector{Float64}) || (typeof(η) == Float64) || (isa(η,Function)) "η must be Float64, Vector{Float64} or Function, got $(typeof(η))"  
        if isa(η,Function)
            try; η = η(;kwargs...); catch; error("error in function η -- check kwargs"); end
            @assert length(η) == length(ϕ) "η must return a vector of the same length as ϕ"
        elseif typeof(η) == Vector{Float64}
            @assert length(η) == length(ϕ) "η must be the same length as ϕ"
        end
        
        @assert (typeof(ϕ) == Vector{Float64}) || (typeof(ϕ) == Float64) "ϕ must be Float64 or Vector{Float64}, got $(typeof(ϕ))"
        @assert (typeof(ϕ₀) == Vector{Float64}) || (typeof(ϕ₀) == Float64) "ϕ₀ must be Float64 or Vector{Float64}, got $(typeof(ϕ₀))"

        @assert (typeof(v) == Vector{Float64}) || (typeof(v) == Float64) || (isa(v,Function)) "v must be Float64, Vector{Float64} or Function, got $(typeof(v))"
        if isa(v,Function)
            try; v = v(;kwargs...); catch; error("error in function v -- check kwargs"); end
            @assert length(v) == length(ϕ) "v must return a vector of the same length as ϕ"
        elseif typeof(v) == Vector{Float64}
            @assert length(v) == length(ϕ) "v must be the same length as ϕ"
        end
        @assert typeof(v) == typeof(ϕ) "v and ϕ must be the same type"

        @assert (typeof(I) == Vector{Float64}) || (typeof(I) == Float64) || (typeof(I) == Matrix{Float64}) || (isa(I,Function)) "I must be Float64, Vector{Float64}, Matrix{Float64}, or Function, got $(typeof(I))"
        if isa(I,Function)
            try; I = I(;kwargs...); catch; error("error in function I -- check kwargs"); end
            if length(r) == 1
                @assert length(I) == length(ϕ) "I must return a vector of the same length as ϕ"
                @assert typeof(I) == typeof(ϕ) "I and ϕ must be the same type"
            elseif typeof(I) == Matrix{Float64}
                @assert size(I) == (length(r),length(ϕ)) "I must return a matrix of size (length(r),length(ϕ))"
            elseif typeof(I) == Vector{Float64}
                @assert length(I) == length(ϕ) && length(I) == length(r) "I must be the same length as ϕ and r"
            else
                error("Invalid return type for function I (got $(typeof(I))): must return Vector{Float64} with length(ϕ) = length(r) or Matrix{Float64} with size (length(r),length(ϕ))")
            end
        elseif typeof(I) == Vector{Float64}
            @assert length(I) == length(ϕ) "I must be the same length as ϕ"
        elseif typeof(I) == Matrix{Float64}
            @assert size(I) == (length(r),length(ϕ)) "I must be a matrix of size (length(r),length(ϕ))"
        end

        @assert (typeof(τ) == Vector{Float64}) || (typeof(τ) == Float64) || (typeof(τ) == Matrix{Float64}) || (isa(τ,Function)) "τ must be Float64, Vector{Float64}, Matrix{Float64}, or Function, got $(typeof(τ))"
        if isa(τ,Function)
            try; τ = τ(;kwargs...); catch; error("error in function τ -- check kwargs"); end
            if length(r) == 1
                @assert length(τ) == length(ϕ) "τ must return a vector of the same length as ϕ"
                @assert typeof(τ) == typeof(ϕ) "τ and ϕ must be the same type"
            elseif typeof(τ) == Matrix{Float64}
                @assert size(τ) == (length(r),length(ϕ)) "τ must return a matrix of size (length(r),length(ϕ))"
            elseif typeof(τ) == Vector{Float64}
                @assert length(τ) == length(ϕ) && length(τ) == length(r) "τ must be the same length as ϕ and r"
            else
                error("Invalid return type for function τ (got $(typeof(τ))): must return Vector{Float64} with length(ϕ) = length(r) or Matrix{Float64} with size (length(r),length(ϕ))")
            end
        elseif typeof(τ) == Vector{Float64}
            @assert length(τ) == length(ϕ) "τ must be the same length as ϕ"
        elseif typeof(τ) == Matrix{Float64}
            @assert size(τ) == (length(r),length(ϕ)) "τ must be a matrix of size (length(r),length(ϕ))"
        elseif typeof(τ) == Float64
            @assert τ>=0.0 "τ must be greater than or equal to 0"
        end

        new{Vector{Float64},Float64}(r,i,rot,θₒ,v,I,ϕ,ϕ₀,ΔA,reflect,τ,η)
    end
end

Base.show(io::IO, r::ring) = begin
    println(io, "ring struct with inclination $(round(r.i,sigdigits=3)) rad, rotation $(round(r.rot,sigdigits=3)) rad, and opening angle $(round(r.θₒ,sigdigits=3)) rad")
    xMin = nothing; xMax = nothing
    if typeof(r.ϕ) == Float64
        if r.ϕ != r.ϕ₀
            println(io, "cloud with final azimuthal angle: $(round(r.ϕ,sigdigits=3)) rad and initial azimuthal angle: $(round(r.ϕ₀,sigdigits=3)) rad")
        else
            println(io, "cloud with final azimuthal angle: $(round(r.ϕ,sigdigits=3)) rad")
        end
        if r.reflect
            println("\t--cloud originally on back side of disk, reflected across disk mid-plane to front")
        end
    else
        try 
            xMin = minimum(i for i in r.ϕ if !isnan(i))
            xMax = maximum(i for i in r.ϕ if !isnan(i)) 
        catch 
            xMin = NaN
            xMax = NaN 
        end
        println(io, "intensity distributed over $(length(r.ϕ)) azimuthal angles ($(round(xMin,sigdigits=3)) < ϕ < $(round(xMax,sigdigits=3)) rad)")
    end
    if typeof(r.r) == Float64
        println(io, "cloud at radius: $(r.r) rₛ")
    else
        try 
            xMin = minimum(i for i in r.r if !isnan(i))
            xMax = maximum(i for i in r.r if !isnan(i)) 
        catch 
            xMin = NaN
            xMax = NaN 
        end
        println(io, "intensity distributed over $(length(r.r)) radii ($(round(xMin,sigdigits=3)) < r < $(round(xMax,sigdigits=3)) rₛ)")
    end
    if typeof(r.v) == Float64
        println(io, "cloud line of sight velocity: $(round(r.v,sigdigits=3)) c")
    else
        try 
            xMin = minimum(i for i in r.v if !isnan(i))
            xMax = maximum(i for i in r.v if !isnan(i)) 
        catch 
            xMin = NaN
            xMax = NaN 
        end
        println(io, "line of sight velocity: $(round(xMin,sigdigits=3)) < v < $(round(xMax,sigdigits=3)) c")
    end
    if typeof(r.I) == Float64
        println(io, "cloud intensity: $(round(r.I,sigdigits=3)) arbitrary units")
    else
        try
            xMin = minimum(i for i in r.I if !isnan(i))
            xMax = maximum(i for i in r.I if !isnan(i))
        catch
            xMin = NaN
            xMax = NaN
        end
        println(io, "intensity: $(round(xMin,sigdigits=3)) < I < $(round(xMax,sigdigits=3)) arbitrary units")
    end
    if typeof(r.τ) == Float64
        println(io, "cloud optical depth: $(round(r.τ,sigdigits=3))")
    else
        try
            xMin = minimum(i for i in r.τ if !isnan(i))
            xMax = maximum(i for i in r.τ if !isnan(i))
        catch
            xMin = NaN
            xMax = NaN
        end
        println(io, "τ: $(round(xMin,sigdigits=3)) < τ < $(round(xMax,sigdigits=3))")
    end
    if typeof(r.ΔA) == Float64
        println(io, "projected area: $(round(r.ΔA,sigdigits=3)) rₛ²")
    else
        try
            xMin = minimum(i for i in r.ΔA if !isnan(i))
            xMax = maximum(i for i in r.ΔA if !isnan(i))
        catch
            xMin = NaN
            xMax = NaN
        end
        println(io, "projected area: $(round(xMin,sigdigits=3)) < ΔA < $(round(xMax,sigdigits=3)) rₛ²")
    end
    if typeof(r.η) == Float64
        println(io, "η: $(round(r.η,sigdigits=3))")
    else   
        try
            xMin = minimum(i for i in r.η if !isnan(i))
            xMax = maximum(i for i in r.η if !isnan(i))
        catch
            xMin = NaN
            xMax = NaN
        end
        println(io, "η: $(round(xMin,sigdigits=3)) < η < $(round(xMax,sigdigits=3))")
    end
end

@kwdef struct profile
    """profile struct to hold binned data, usually set to model struct with profiles.jl#setProfile
    attributes:
        name: name of profile {Symbol}
        centers: bin centers {Vector{Float64}}
        edges: bin edges {Vector{Float64}}
        sums: sum of values in each bin {Vector{Float64}}
    """
    name::Symbol
    binCenters::Vector{Float64}
    binEdges::Vector{Float64}
    binSums::Vector{Float64}
end

Base.show(io::IO, p::profile) = begin
    println(io, "$(p.name) profile struct with $(length(p.binCenters)) bins")
end

struct ray
    """ray struct to hold raytraced data
    attributes:
        rCam: distance from image center (in terms of rₛ) {Float64}
        ϕCam: azimuthal angle of ray at camera (rad) {Float64}
        α: x value at camera {Float64}
        β: y value at camera {Float64}
        τ: optical depths seen by ray {Vector{Float64}} -- this is the value after ray has passed through each given point
        x: x values of strikes along ray {Vector{Float64}}
        I: intensity values accumulated along ray {Vector{Float64}}
        zone: zone of ray {Int}
    """
    rCam::Float64
    ϕCam::Float64
    α::Float64
    β::Float64
    τ::Vector{Float64}
    x::Vector{Float64}
    I::Vector{Float64}
    zone::Int
end
Base.show(io::IO, r::ray) = begin
    println(io, "ray struct with distance from image center $(round(r.rCam,sigdigits=3)) rₛ and azimuthal angle $(round(r.ϕCam,sigdigits=3)) rad")
end

mutable struct camera #need to modify to include "imgs" of each quantity -- most importantly v and I after raytracing
    """camera coordinates struct
    attributes:
        α: x values Union{Vector{Float64}, Matrix{Float64}} 
        β: y values Union{Vector{Float64}, Matrix{Float64}
        rays: ray traced rays Union{Nothing,Vector{Float64},Matrix{Float64}}
            - optional, if provided, will be used to generate images
    """
    α::Union{Vector{Float64},Matrix{Float64}}
    β::Union{Vector{Float64},Matrix{Float64}}
    rays::Union{Nothing,Vector{ray}}
end

Base.show(io::IO, c::camera) = begin
    pix = length(c.α)
    println(io, "camera with $pix pixels and range: $(round(minimum(c.α),sigdigits=3)) < α < $(round(maximum(c.α),sigdigits=3)) and $(round(minimum(c.β),sigdigits=3)) < β < $(round(maximum(c.β),sigdigits=3))")
    if !isnothing(c.rays)
        println(io, "containing $(length(c.rays)) rays")
    else
        println(io, "no rays (call raytrace! to generate)")
    end
end 

meshgrid(x,y) = (reshape(repeat(x,outer=length(y)),length(x),length(y)), reshape(repeat(y,inner=length(x)),length(x),length(y)))

mutable struct model
    #make immutable to see if improves performance cost?
    #add image as keyword arg to constructors -- only initialize if true to save on performance
    
    """structure to hold many rings and their parameters
    attributes:
        rings: Vector{ring}
            - list of ring objects
        profiles: Union{Nothing,Dict{Symbol,profile}}
            - dictionary of profiles (see profile struct) with keys as symbols
            - optional, usually initialized to empty dictionary and filled in with setProfile!
        camera: Union{Nothing,camera}
            - camera coordinates (α,β) corresponding to each ring used to generate images and in raytracing
        subModelStartInds: Vector{Int}
            - indices of start of each submodel in list of rings
            - used to separate out submodels for raytracing or for the recovery of individual models after being combined
    """
    rings::Vector{ring}
    profiles::Union{Nothing,Dict{Symbol,profile}}
    camera::Union{Nothing,camera}
    subModelStartInds::Vector{Int} #indices of start of each submodel in list of rings
    #note: move α,β for every point (as currently defined) to new struct -- camera α and β should be user defined and separate
    #also keep track of xyz in this new struct? call it coords and have one field be camera and the other be system
    #or just put it in each ring? probably less cluttered/better...do tomorrow

    function model(rings::Vector{ring{Vector{Float64},Float64}},profiles::Union{Nothing,Dict{Symbol,profile}},camera::Union{Nothing,camera},subModelStartInds::Vector{Int})
        """
        constructor for model struct -- takes in rings, profiles, camera, and subModelStartInds and returns a model object (detailed above) while checking for errors
        """
        new(rings,profiles,camera,subModelStartInds)
    end

    function model(rings::Vector{ring{Vector{Float64},Float64}})
        """
        constructor for model struct -- takes in rings and returns a model object (detailed above) while checking for errors
        """
        r = [ring.r for ring in rings]; ϕ₀ = [ring.ϕ₀ for ring in rings]; i = [ring.i for ring in rings]; rot = [ring.rot for ring in rings]; θₒ = [ring.θₒ for ring in rings]; reflect = [ring.reflect for ring in rings]
        α = zeros(length(r)); β = zeros(length(r))
        for (i,(ri,ϕi,ii,roti,θₒi,reflecti)) in enumerate(zip(r,ϕ₀,i,rot,θₒ,reflect))
            α[i], β[i] = photograph(ri,ϕi,ii,roti,θₒi,reflecti)  #get camera coordinates from physical 
        end
        new(rings,Dict{Symbol,profile}(),camera(stack(α,dims=1),stack(β,dims=1),nothing),[1])
    end

    function model(rMin::Float64, rMax::Float64, i::Float64, nr::Int, nϕ::Int, I::Function, v::Function, scale::Symbol; kwargs...)
        """constructor for model struct -- takes in rMin, rMax, i, nr, nϕ, I, v, and scale and returns a model object (detailed above) while checking for errors
        params:
            rMin: minimum radius of model (in terms of rₛ) {Float64}
            rMax: maximum radius of model (in terms of rₛ) {Float64}
            i: inclination angle (rad) {Float64} (all rings have the same inclination)
            rot: rotation of system plane about z axis (rad) {Float64}
            nr: number of radial bins {Int}
            nϕ: number of azimuthal bins {Int}
            I: intensity function {Function} (defaults to DiskWindIntensity)
            v: velocity function {Function} (defaults to vCircularDisk)
            scale: radial binning scale (:log or :linear)
            kwargs: extra keyword arguments for I and v if they are functions (see examples)
        returns:
            model object {model}
        """
        r = nothing; ΔA = nothing
        @assert rMin < rMax "rMin must be less than rMax"
        @assert nr > 0 "nr must be greater than 0"
        @assert nϕ > 0 "nϕ must be greater than 0"

        ϕ = collect(range(-π,stop=π,length=nϕ)) #non-rotated frame
        Δϕ = ϕ[2] - ϕ[1]
        if scale == :log        
            logr = collect(range(log(rMin*cos(i)),stop=log(rMax),length=nr))
            Δr = logr[2] - logr[1]
            r = exp.(logr)
        elseif scale == :linear
            r = collect(range(rMin*cos(i),stop=rMax,length=nr))
            Δr = r[2] - r[1]
        else
            error("scale must be :log or :linear")
        end

        rMesh, ϕMesh = meshgrid(r,ϕ) #camera r,ϕ
        α = rMesh .* cos.(ϕMesh); β = rMesh .* sin.(ϕMesh) #camera coordinates
        ΔA = scale == :log ? rMesh.^2 .* (Δr * Δϕ) : rMesh .* (Δr * Δϕ) #projected disk area, normalization doesn't matter
        rSystem = zeros(nr,nϕ); ϕSystem = zeros(nr,nϕ); ϕ₀ = zeros(nr,nϕ); η = zeros(nr,nϕ)
        θₒ = 0.0; rot = 0.0
        r3D = get_r3D(i,rot,θₒ) 
        xyz = [0.0;0.0;0.0]
        matBuff = zeros(3,3)
        colBuff = zeros(3)
        rt = 0.0; ϕt = 0.0; ϕ₀t = 0.0 #preallocate raytracing variables
        for ri in 1:nr
            for ϕi in 1:nϕ
                rt, ϕt, ϕ₀t = raytrace(α[ri,ϕi], β[ri,ϕi], i, rot, θₒ, r3D, xyz, matBuff, colBuff) #flip i to match convention of +z being up, relic
                ηt = response(rt; kwargs...) #response function
                # println("RAYTRACE: rt = $rt, ϕt = $ϕt, ϕ₀t = $ϕ₀t")
                # x = β[ri,ϕi]/cos(i); y = α[ri,ϕi]; z = 0.0 #system coordinates from camera coordinates, raytraced back to disk plane
                # rt = sqrt(x^2 + y^2 + z^2); ϕt = atan(y,x); ϕ₀t = atan(y,x) #convert to polar coordinates
                # println("OLD WAY: rt = $rt, ϕt = $ϕt, ϕ₀t = $ϕ₀t")
                # exit()
                if rt < rMin || rt > rMax #exclude portions outside of (rMin, rMax)
                    rSystem[ri,ϕi], ϕSystem[ri,ϕi], ϕ₀[ri,ϕi], η[ri,ϕi] = NaN, NaN, NaN, NaN
                else
                    rSystem[ri,ϕi], ϕSystem[ri,ϕi], ϕ₀[ri,ϕi], η[ri,ϕi] = rt, ϕt, ϕ₀t, ηt
                end
            end
        end

        rSystem = [rSystem[i,:] for i in 1:nr]; ϕSystem = [ϕSystem[i,:] for i in 1:nr]; ΔA = [ΔA[i,:] for i in 1:nr]; ϕ₀ = [ϕ₀[i,:] for i in 1:nr]; η = [η[i,:] for i in 1:nr] #reshape, correct ϕ for other functions (based on ϕ to observer with ϕ = 0 at camera)
        rings = [ring(r = ri, i = i, v = v, I = I, ϕ = ϕi, ϕ₀ = ϕ₀i, ΔA = ΔAi, rMin=rMin, rMax=rMax, rot=rot, θₒ=θₒ, η=ηi; kwargs...) for (ri,ϕi,ΔAi,ϕ₀i,ηi) in zip(rSystem,ϕSystem,ΔA,ϕ₀,η)]
        m = new(rings,Dict{Symbol,profile}(),camera(stack(α,dims=1),stack(β,dims=1),nothing),[1])
    end

    function model(r̄::Float64, rFac::Float64, Sα::Float64, i::Float64, nr::Int, nϕ::Int, scale::Symbol; kwargs...)
        """constructor for model struct -- takes in r̄, Sα, i, nr, nϕ, scale, and kwargs and returns a model object (detailed above) while checking for errors
        this version of the constructor creates a DiskWind model of the BLR as detailed in Long+2023
        params:
            r̄: mean radius of model (in terms of rₛ) {Float64}
            Sα: radius factor {Float64} 
            i: inclination angle (rad) {Float64}
            nr: number of radial bins {Int}
            nϕ: number of azimuthal bins {Int}
            scale: radial binning scale (:log or :linear)
            kwargs: extra keyword arguments for model constructor (see examples)
        returns:
            model object {model}
        """
        @assert (Sα != 1/2) && (Sα != 3/2) "Sα cannot be 1/2 or 3/2 as this divides by zero"
        @assert r̄ > 0 "r̄ must be greater than 0"

        rMin, rMax = get_rMinMaxDiskWind(r̄,rFac,Sα)
        # println("r̄ = $r̄, rMin = $rMin, rMax = $rMax")
        kwargs = values(kwargs); kwargs = merge(kwargs, (; α = Sα))
        # println("kwargs = $kwargs")
        model(rMin, rMax, i, nr, nϕ, DiskWindIntensity, vCircularDisk, scale; kwargs...)
    end
end

function DiskWindModel(rMin::Float64, rMax::Float64, i::Float64; nr::Int=128, nϕ::Int=256, I::Function=DiskWindIntensity, v::Function=vCircularDisk, scale::Symbol=:log, kwargs...)
    """uses the model constructor to create a DiskWind model of the BLR as detailed in Long+2023 and Long+2025
    params: (similar to function below but must explicitly pass rMin and rMax)
        rMin: minimum radius of model (in terms of rₛ) {Float64}
        rMax: maximum radius of model (in terms of rₛ) {Float64}
        i: inclination angle (rad) {Float64} (all rings have the same inclination)
        nr: number of radial bins {Int}
        nϕ: number of azimuthal bins {Int}
        I: intensity function {Function} (defaults to DiskWindIntensity)
        v: velocity function {Function} (defaults to vCircularDisk)
        scale: radial binning scale (:log or :linear)
        kwargs: extra keyword arguments for I and v if they are functions (see examples)
    returns:
        model object {model}
    """
    return model(rMin, rMax, i, nr, nϕ, I, v, scale; kwargs...)
end

function DiskWindModel(r̄::Float64, rFac::Float64, α::Float64, i::Float64; rot::Float64=0.0, nr::Int=128, nϕ::Int=256, scale::Symbol=:log, kwargs...)
    """uses the model constructor to create a DiskWind model of the BLR as detailed in Long+2023 and Long+2025
    params: (similar to function above but here we pass r̄, rFac, and α)
        r̄: mean radius of model (in terms of rₛ) {Float64}
        rFac: radius factor {Float64} 
        α: power-law source function scaling {Float64} 
        i: inclination angle (rad) {Float64}
        rot: rotation of system plane about z axis (rad) {Float64}
        nr: number of radial bins {Int}
        nϕ: number of azimuthal bins {Int}
        scale: radial binning scale (:log or :linear)
        kwargs: extra keyword arguments for model constructor (see examples)
    returns:
        model object {model}
    """
    return model(r̄, rFac, α, i, nr, nϕ, scale; kwargs...)
end

function cloudModel(ϕ₀::Vector{Float64}, i::Vector{Float64}, rot::Vector{Float64}, θₒ::Vector{Float64}, θₒSystem::Float64, ξ::Float64; rₛ::Float64=1.0, μ::Float64=500., β::Float64=1.0, F::Float64=0.5,
    I::Union{Function,Float64}=IsotropicIntensity,v::Union{Function,Float64}=vCircularCloud,kwargs...)
    """uses the model constructor to create a cloud model of the BLR similar to Pancoast+ 2011 and 2014
    params: (similar to function below but here we must explicitly pass ϕ₀, i, rot, and θₒ)
        ϕ₀: initial azimuthal angle of cloud (rad) {Vector{Float64}}
        i: inclination angle (rad) {Vector{Float64}} 
        rot: rotation of system plane about z axis (rad) {Vector{Float64}}
        θₒ: opening angle of cloud (rad) {Vector{Float64}}
        θₒSystem: opening angle of system (rad) {Float64}
        ξ: power-law source function scaling {Float64} 
        rₛ: scale radius (in terms of rₛ) {Float64}
        μ: mean radius of model (in terms of rₛ) {Float64}
        β: shape parameter for radial distribution {Float64} 
        F: minimum fraction of maximum radius where clouds can be placed {Float64}
        I: intensity function {Function} (defaults to IsotropicIntensity)
        v: velocity function {Function} (defaults to vCircularCloud)
        kwargs: extra keyword arguments for I and v if they are functions (see examples)
    returns:
        model object {model}
    """
    @assert length(ϕ₀) == length(i) == length(rot) == length(θₒ) "ϕ, i, rot, and θₒ must be the same length -- got $(length(ϕ)), $(length(i)), $(length(rot)), and $(length(θₒ))"
    rings = [drawCloud(i=i[j],θₒ=θₒ[j],rot=rot[j],ϕ₀=ϕ₀[j],μ=μ,F=F,β=β,rₛ=rₛ,θₒSystem=θₒSystem,I=I,v=v,ξ=ξ;kwargs...) for j=1:length(ϕ₀)]
    return model(rings)
end

function cloudModel(nClouds::Int64; μ::Float64=500., β::Float64=1.0, F::Float64=0.5, rₛ::Float64=1.0, θₒ::Float64=π/2, γ::Float64=1.0, ξ::Float64=1.0, i::Float64=0.0, 
    I::Union{Function,Float64}=IsotropicIntensity, v::Union{Function,Float64}=vCircularCloud, rng::AbstractRNG=Random.GLOBAL_RNG, kwargs...)
    """uses the model constructor to create a cloud model of the BLR similar to Pancoast+ 2011 and 2014
    params: (similar to above but using multiple dispatch here we pass nClouds and generate random values for ϕ₀, rot, and θₒ while keeping i constant for the system)
        nClouds: number of clouds {Int}
        μ: mean radius of model (in terms of rₛ) {Float64}
        β: shape parameter for radial distribution {Float64} 
        F: minimum fraction of maximum radius where clouds can be placed {Float64}
        rₛ: scale radius (in terms of rₛ) {Float64}
        θₒ: maximum opening angle of cloud distribution (rad) {Float64}
        γ: disk concentration parameter {Float64} 
        ξ: power-law source function scaling {Float64} 
        i: inclination angle (rad) {Float64}
        I: intensity function {Function} (defaults to IsotropicIntensity)
        v: velocity function {Function} (defaults to vCircularCloud)
        rng: random number generator {AbstractRNG}
        kwargs: extra keyword arguments for I and v if they are functions (see examples)
    returns:
        model object {model}
    """
    ϕ₀ = rand(rng,nClouds).*2π
    #θₒ = rand(nClouds).*θₒ #note: need to implement equation 13 here -- should add a system θₒ parameter to ring (or model?) struct, then each ring can have a different θ
    θ = acos.(cos(θₒ).+(1-cos(θₒ)).*rand(rng,nClouds).^γ) #θₒ for each cloud, from eqn 14
    rot = rand(rng,nClouds).*2π
    i = ones(nClouds).*i
    return cloudModel(ϕ₀,i,rot,θ,θₒ,ξ, rₛ=rₛ,μ=μ,β=β,F=F,I=I,v=v,rng=rng;kwargs...)
end

Base.show(io::IO, m::model) = begin 
    println(io, "model struct with $(length(m.rings)) rings:")
    if isdefined(m, :profiles) && length(m.profiles) > 0
        println(io, "\t-profiles: $(keys(m.profiles))")
    else
        println(io, "\t-no profiles set")
    end
    if isdefined(m, :camera)
        println(io, "\t-$(m.camera)")
    else
        println(io, "\t-no camera set")
    end
end
