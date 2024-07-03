#!/usr/bin/env julia

function getΨ(m::model,vEdges::Array{Float64},tEdges::Array{Float64};)
    I = getVariable(m,:I)
    ΔA = getVariable(m,:ΔA)
    v = getVariable(m,:v)
    d(ring::ring) = (typeof(ring.r[1]) == Float64 && typeof(ring.ϕ[1]) == Float64) ? tCloud(ring) : tDisk(ring)
    delays = getVariable(m,d)
    Ψ = Array{Float64}(undef,length(vEdges)-1,length(tEdges)-1)
    for i in 1:length(vEdges)-1
        for j in 1:length(tEdges)-1
            mask = (v .>= vEdges[i]) .& (v .< vEdges[i+1]) .& (delays .>= tEdges[j]) .& (delays .< tEdges[j+1])
            s = sum(I[mask].*ΔA[mask])
            Ψ[i,j] = s > 0 ? s : 1e-30
        end
    end
    return Ψ
end

function getΨ(m::model,vBins::Int64,tBins::Int64)
    v = getVariable(m,:v)
    t(ring::ring) = (typeof(ring.r[1]) == Float64 && typeof(ring.ϕ[1]) == Float64) ? tCloud(ring) : tDisk(ring)
    delays = getVariable(m,t)
    maxV =  maximum(i for i in v if !isnan(i))
    minV =  minimum(i for i in v if !isnan(i))
    maxT =  maximum(i for i in delays if !isnan(i))
    minT =  minimum(i for i in delays if !isnan(i))
    vEdges = collect(range(minV,stop=maxV,length=vBins+1))
    tEdges = collect(range(minT,stop=maxT,length=tBins+1))
    vCenters = @. (vEdges[1:end-1] + vEdges[2:end])/2
    tCenters = @. (tEdges[1:end-1] + tEdges[2:end])/2
    return vCenters,tCenters,getΨ(m,vEdges,tEdges)
end

function getΨt(m::model,tEdges::Array{Float64})
    I = getVariable(m,:I)
    ΔA = getVariable(m,:ΔA)
    d(ring::ring) = (typeof(ring.r[1]) == Float64 && typeof(ring.ϕ[1]) == Float64) ? tCloud(ring) : tDisk(ring)
    delays = getVariable(m,d)
    Ψt = Array{Float64}(undef,length(tEdges)-1)
    for j in 1:length(tEdges)-1
        mask = (delays .>= tEdges[j]) .& (delays .< tEdges[j+1])
        s = sum(I[mask].*ΔA[mask])
        Ψt[j] = s > 0 ? s : 1e-30
    end
    return Ψ
end

function getΨt(m::model,tBins::Int64)
    t(ring::ring) = (typeof(ring.r[1]) == Float64 && typeof(ring.ϕ[1]) == Float64) ? tCloud(ring) : tDisk(ring)
    delays = getVariable(m,t)
    maxT =  maximum(i for i in delays if !isnan(i))
    minT =  minimum(i for i in delays if !isnan(i))
    tEdges = collect(range(minT,stop=maxT,length=tBins+1))
    tCenters = @. (tEdges[1:end-1] + tEdges[2:end])/2
    return tCenters,getΨt(m,tEdges)
end