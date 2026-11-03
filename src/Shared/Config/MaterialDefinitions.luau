-- Material drives the corrosion name shown to players and which sound and particle set
-- the client uses. It does not change restoration math; stages and tools do.
return {
	Iron = { DisplayName = "Iron", Corrosion = "Rust", SoundSet = "Rust", ParticleSet = "RustFlakes" },
	CastIron = { DisplayName = "Cast Iron", Corrosion = "Heavy Rust", SoundSet = "Rust", ParticleSet = "RustFlakes" },
	Steel = { DisplayName = "Steel", Corrosion = "Rust", SoundSet = "Rust", ParticleSet = "RustFlakes" },
	Brass = { DisplayName = "Brass", Corrosion = "Tarnish", SoundSet = "SoftMetal", ParticleSet = "Grime" },
	Copper = { DisplayName = "Copper", Corrosion = "Verdigris", SoundSet = "SoftMetal", ParticleSet = "Verdigris" },
	Bronze = { DisplayName = "Bronze", Corrosion = "Verdigris", SoundSet = "SoftMetal", ParticleSet = "Verdigris" },
	Silver = { DisplayName = "Silver", Corrosion = "Tarnish", SoundSet = "SoftMetal", ParticleSet = "Grime" },
	Gold = { DisplayName = "Gold", Corrosion = "Grime", SoundSet = "SoftMetal", ParticleSet = "Grime" },
	Pewter = { DisplayName = "Pewter", Corrosion = "Grime", SoundSet = "SoftMetal", ParticleSet = "Grime" },
	Mixed = { DisplayName = "Mixed Materials", Corrosion = "Rust and Grime", SoundSet = "Rust", ParticleSet = "RustFlakes" },
}
