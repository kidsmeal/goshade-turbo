// Vortex disc: every particle orbits the emitter, angular speed grows with
// radius (rps = base_rps + rps_per_100px * r / 100). Pair with
// vortex_portal.tscn, where the GoShade Turbo metaball_portal export merges
// the soft circles into one blob. Hand-written particles shader, not a
// GoShade Turbo stack (docs/DESIGN.md expansions: particles stack type).
shader_type particles;

uniform float disc_radius = 100.0;
uniform float base_rps = 0.025;       // rotations per second at the centre
uniform float rps_per_100px = 0.05;  // added rotations per second per 100 px of radius
uniform float drift = 1;          // outward px per second; 0 keeps every radius fixed
uniform float fade = 0.15;          // fraction of lifetime spent growing in and shrinking out

float rand(uint seed, uint salt) {
	uint n = seed * 747796405u + salt * 2891336453u;
	n = ((n >> 13u) ^ n) * 2654435769u;
	return float(n & 16777215u) / 16777216.0;
}

void start() {
	uint seed = RANDOM_SEED + NUMBER * 7919u;
	float r = disc_radius * sqrt(rand(seed, 1u));
	float a = TAU * rand(seed, 2u);
	TRANSFORM = mat4(1.0);
	TRANSFORM[3].xy = vec2(cos(a), sin(a)) * r;
	VELOCITY = vec3(0.0);
	COLOR = vec4(1.0);
	CUSTOM = vec4(0.0);
}

void process() {
	vec2 p = TRANSFORM[3].xy;
	float r = length(p);
	float da = TAU * (base_rps + rps_per_100px * r / 50.0) * DELTA;
	float c = cos(da);
	float s = sin(da);
	p = vec2(p.x * c - p.y * s, p.x * s + p.y * c);
	if (drift != 0.0 && r > 0.0) {
		p += p / r * drift * DELTA;
	}
	TRANSFORM[3].xy = p;

	// CUSTOM.y is the lifetime phase in [0, 1], same convention as
	// ParticleProcessMaterial. Grow in and shrink out so respawns do not
	// pop. Scale, not alpha: a half-alpha disc reads as mid luma across its
	// whole core, and the portal's edge band would paint the entire ball.
	CUSTOM.y = min(CUSTOM.y + DELTA / LIFETIME, 1.0);
	float t = CUSTOM.y;
	float grow = smoothstep(0.0, fade, t) * smoothstep(1.0, 1.0 - fade, t);
	TRANSFORM[0].xy = vec2(grow, 0.0);
	TRANSFORM[1].xy = vec2(0.0, grow);
}
