using ParticleInCell2
using CairoMakie
CairoMakie.activate!(type = "svg") #hide
set_theme!(theme_light()) #hide

sim_length = 1.0
number_density = 1e14
num_macroparticles = 320
particles_per_macro = number_density * sim_length / num_macroparticles

positions = collect(0:num_macroparticles-1) ./ num_macroparticles;

k = 1 * 2pi / sim_length
amplitude = 1e3
elec_mass = 9e-31
momentums = (particles_per_macro * elec_mass * amplitude) .* sin.(positions .* k);

scatter(
    positions,
    momentums;
    axis = (;
        title = "Electron phase space",
        xlabel = "Position (m)",
        ylabel = "Momentum (kg m / s)",
    ),
)

electrons = ParticleInCell2.electrons(positions, momentums, particles_per_macro);

num_cells = 32
dx = sim_length / num_cells
periodic = true
grid = UniformCartesianGrid((0.0,), (sim_length,), (num_cells,), (periodic,));

field_dimension = 1
lower_guard_cells = 1
rho = Field(grid, ParticleInCell2.node, field_dimension, lower_guard_cells)
phi = Field(grid, ParticleInCell2.node, field_dimension, lower_guard_cells)
Eedge = Field(grid, ParticleInCell2.edge, field_dimension, lower_guard_cells)
Enode = Field(grid, ParticleInCell2.node, field_dimension, lower_guard_cells);

epsilon_0 = 8.8e-12
elec_charge = 1.6e-19
elec_mass = 9e-31
expected_plasma_freq = sqrt(number_density * elec_charge^2 / elec_mass / epsilon_0)
expected_plasma_period = 2pi / expected_plasma_freq

dt = 5e-11

charge_interp = BSplineChargeInterpolation(electrons, rho, 1)
comm_rho = CommunicateGuardCells(rho, true)
field_solve = PoissonSolveFFT(rho, phi)
comm_phi = CommunicateGuardCells(phi)
finite_diff = FiniteDifferenceToEdges(phi, Eedge)
comm_Eedge = CommunicateGuardCells(Eedge)
elec_ave = AverageEdgesToNodes(Eedge, Enode)
comm_Enode = CommunicateGuardCells(Enode)
push = ElectrostaticParticlePush(electrons, Enode, dt)
comm_electrons = CommunicateSpecies(electrons, grid);

n_steps = 1000

electric_field_energy = Vector{Float64}(undef, n_steps)

for n = 1:n_steps
    # Calculate the electric field energy
    electric_field_energy[n] = 0
    for I in eachindex(Enode)
        electric_field_energy[n] += (dx * epsilon_0 / 2) * (Enode.values[I])^2
    end

    # TODO
    rho.values .= 0

    step!(charge_interp)
    step!(comm_rho)
    step!(field_solve)
    step!(comm_phi)
    step!(finite_diff)
    step!(comm_Eedge)
    step!(elec_ave)
    step!(comm_Enode)
    step!(push)
    step!(comm_electrons)
end

times = collect(range(1, n_steps)) .* dt
lines(
    times,
    electric_field_energy;
    axis = (; title = "Electric Field Energy", xlabel = "Time (s)", ylabel = "Energy"),
)

using FFTW

freqs = fftfreq(n_steps, 1 / dt) .* 2pi
freq_amps = abs.(fft(electric_field_energy))

lines(
    freqs,
    freq_amps;
    axis = (;
        title = "Electric Field Energy Frequency Spectrum",
        xlabel = "Frequency (1/s)",
        ylabel = "Amplitude",
    ),
)

cutoff_index = round(Int, n_steps * 0.05)
lines(
    freqs[1:cutoff_index],
    freq_amps[1:cutoff_index];
    axis = (;
        title = "Electric Field Energy Frequency Spectrum",
        xlabel = "Frequency (1/s)",
        ylabel = "Amplitude",
    ),
)

freq_amps[1] = 0
max_index = findmax(freq_amps)[2]
max_freq = freqs[max_index]

# Divide by 2 because the electric field energy goes through a maximum twice
# per plasma oscillation, and take the absolute value because we don't care
# about the phase of the oscillation.
plasma_freq = abs(max_freq / 2)

relative_error = (plasma_freq - expected_plasma_freq) / expected_plasma_freq

boltzmann_constant = 1.381e-23
dx^2 * number_density * elec_charge^2 / epsilon_0 / boltzmann_constant

dx^2 * number_density * elec_charge / epsilon_0

function measure_plasma_frequency(number_density, temperature, wavenumber)
    sim_length = 1.0

    num_cells = 32
    dx = sim_length / num_cells

    num_macroparticles = 320
    particles_per_macro = number_density * sim_length / num_macroparticles

    perturb_amplitude = 1e3
    elec_mass = 9e-31
    boltzmann_constant = 1.381e-23
    thermal_velocity = sqrt(3 * boltzmann_constant * temperature / elec_mass)

    positions = collect(0:num_macroparticles-1) ./ num_macroparticles
    momentums =
        (particles_per_macro * elec_mass) .*
        (perturb_amplitude .* sin.(positions .* wavenumber) .+ thermal_velocity .* randn.())

    electrons = ParticleInCell2.electrons(positions, momentums, particles_per_macro)

    grid = UniformCartesianGrid((0.0,), (sim_length,), (num_cells,), (true,))

    field_dimension = 1
    lower_guard_cells = 1
    rho = Field(grid, ParticleInCell2.node, field_dimension, lower_guard_cells)
    phi = Field(grid, ParticleInCell2.node, field_dimension, lower_guard_cells)
    Eedge = Field(grid, ParticleInCell2.edge, field_dimension, lower_guard_cells)
    Enode = Field(grid, ParticleInCell2.node, field_dimension, lower_guard_cells)

    dt = 5e-11
    charge_interp = BSplineChargeInterpolation(electrons, rho, 1)
    comm_rho = CommunicateGuardCells(rho, true)
    field_solve = PoissonSolveFFT(rho, phi)
    comm_phi = CommunicateGuardCells(phi)
    finite_diff = FiniteDifferenceToEdges(phi, Eedge)
    comm_Eedge = CommunicateGuardCells(Eedge)
    elec_ave = AverageEdgesToNodes(Eedge, Enode)
    comm_Enode = CommunicateGuardCells(Enode)
    push = ElectrostaticParticlePush(electrons, Enode, dt)
    comm_electrons = CommunicateSpecies(electrons, grid)

    n_steps = 1000
    electric_field_energy = Vector{Float64}(undef, n_steps)

    epsilon_0 = 8.8e-12
    for n = 1:n_steps
        # Calculate the electric field energy
        electric_field_energy[n] = 0
        for I in eachindex(Enode)
            electric_field_energy[n] += (dx * epsilon_0 / 2) * (Enode.values[I])^2
        end

        # TODO
        rho.values .= 0

        step!(charge_interp)
        step!(comm_rho)
        step!(field_solve)
        step!(comm_phi)
        step!(finite_diff)
        step!(comm_Eedge)
        step!(elec_ave)
        step!(comm_Enode)
        step!(push)
        step!(comm_electrons)
    end

    freqs = fftfreq(n_steps, 1 / dt) .* 2pi
    freq_amps = abs.(fft(electric_field_energy))

    freq_amps[1] = 0
    max_index = findmax(freq_amps)[2]
    max_freq = freqs[max_index]
    plasma_freq = abs(max_freq / 2)

    return plasma_freq
end

temperatures = [0, 0.1, 1, 10]
measure_plasma_frequency.(1e14, temperatures, 1 / 2 * pi)

function warm_plasma_freq(number_density, temperature, wavenumber)
    epsilon_0 = 8.8e-12
    elec_charge = 1.6e-19
    elec_mass = 9e-31
    boltzmann_constant = 1.381e-23
    square_plasma_freq = number_density * elec_charge^2 / elec_mass / epsilon_0
    correction_factor = boltzmann_constant * temperature * wavenumber^2 / elec_mass
    return sqrt(square_plasma_freq + correction_factor)
end
warm_plasma_freq.(1e14, temperatures, 1 / 2 * pi)

# This file was generated using Literate.jl, https://github.com/fredrikekre/Literate.jl
