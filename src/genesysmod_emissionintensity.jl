"""
Internal function used in the run to compute sectoral emissions and emission intensity of fuels.
"""
function genesysmod_emissionintensity(model, Sets, Params, VarPar, Vars, TierFive, LoopSetOutput, LoopSetInput)
    𝓡 = Sets.Region_full
    𝓕 = Sets.Fuel
    𝓨 = Sets.Year
    𝓣 = Sets.Technology
    𝓔 = Sets.Emission
    𝓢𝓮 = Sets.Sector

    SectorEmissions = JuMP.Containers.DenseAxisArray(zeros(length(𝓨),length(𝓡),length(𝓕),length(𝓔)), 𝓨, 𝓡, 𝓕, 𝓔)
    EmissionIntensity = JuMP.Containers.DenseAxisArray(zeros(length(𝓨),length(𝓡),length(𝓕),length(𝓔)), 𝓨, 𝓡, 𝓕, 𝓔)
    #output_emissionintensity;

    for y ∈ 𝓨 for r ∈ 𝓡 for e ∈ 𝓔
        SectorEmissions[y,r,"Power",e] =  sum(value(Vars.AnnualTechnologyEmissionByMode[y,t,e,m,r])*
            Params.OutputActivityRatio[r,t,"Power",m,y] for (t,m) ∈ LoopSetOutput[(r,"Power",y)])

        for f ∈ TierFive
            SectorEmissions[y,r,f,e] = sum(value(Vars.AnnualTechnologyEmissionByMode[y,t,e,m,r])*Params.OutputActivityRatio[r,t,f,m,y] for (t,m) ∈ LoopSetOutput[(r,f,y)])

            if VarPar.ProductionAnnual[y,f,r] != 0
                EmissionIntensity[y,r,f,e] = SectorEmissions[y,r,f,e]/VarPar.ProductionAnnual[y,f,r]
            end
        end

        if sum(value(model[:ProductionByTechnologyAnnual][y,t,"Power",r]) for t ∈ 𝓣 if Params.TagTechnologyToSector[t,"Storages"] == 0) != 0
            EmissionIntensity[y,r,"Power",e] = SectorEmissions[y,r,"Power",e]/
            sum(value(model[:ProductionByTechnologyAnnual][y,t,"Power",r]) for t ∈ 𝓣 if Params.TagTechnologyToSector[t,"Storages"] == 0)
        end
    end end end

    return SectorEmissions, EmissionIntensity
end
