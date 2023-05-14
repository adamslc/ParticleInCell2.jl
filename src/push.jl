struct SimpleParticlePush{S, T} <: AbstractSimulationStep
    species::S
    timestep::T
end

function step!(::Any, step::SimpleParticlePush)
    species = step.species

    species.momentums .+= step.timestep .* species.forces
    # TODO: this doesn't work for variable weight particles
    species.positions .+= (step.timestep / species.mass) .* species.momentums
end
