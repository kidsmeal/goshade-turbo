// Vortex of vortexes: `eye_count` eyes sit on a ring of radius `ring_radius`
// (plus one at the origin when `centre_eye` is on). The ring rotates at
// `disc_rps`; inside each eye its particles orbit the eye centre at that
// eye's own speed and direction (`eye_rps` scaled by a per-eye hash in
// [1 - eye_rps_variance, 1 + eye_rps_variance], odd eyes reversed when
// `alternate_spin` is on), plus `eye_rps_differential` scaled by how close
// they sit to the core so inner particles lead. Local radius is sampled in
// [core_radius, eye_radius]. Pair with vortex_portal.tscn, where the GoShade
// Turbo metaball_portal export merges the soft circles into one blob.
// Hand-written particles shader, not a GoShade Turbo stack (docs/DESIGN.md
// expansions: particles stack type).
//
// CUSTOM layout: x = eye index (centre eye = eye_count), y = lifetime phase,
// z = local orbit angle, w = local orbit radius. COLOR.a = per-ball size.
shader_type particles;

uniform int eye_count : hint_range(1, 8) = 5;
uniform bool centre_eye = true;
uniform bool alternate_spin = true;
uniform float ring_radius = 100.0;
uniform float eye_radius = 70.0;
uniform float core_radius = 20.0;
uniform float disc_rps = 0.03;              // ring rotations per second
uniform float eye_rps = 0.15;               // orbit rotations per second inside an eye
uniform float eye_rps_variance : hint_range(0.0, 1.0) = 0.5; // per-eye speed spread around eye_rps
uniform float eye_rps_differential = 0.1;   // extra rps at core_radius, 0 at eye_radius
uniform float drift = -4.0;                 // px per second along the local radius; negative pulls toward the eye core
uniform float fade = 0.15;                  // fraction of lifetime spent growing in and shrinking out
uniform float ball_scale = 1.0;             // base size multiplier on the particle texture
uniform float ball_scale_random : hint_range(0.0, 1.0) = 0.0; // per-particle size spread: each ball is ball_scale * [1 - r, 1 + r]
uniform float spawn_random : hint_range(0.0, 1.0) = 1.0;      // 0 = every eye gets an even share of balls, 1 = eye picked at random per ball

float rand(uint seed, uint salt) {
	uint n = seed * 747796405u + salt * 2891336453u;
	n = ((n >> 13u) ^ n) * 2654435769u;
	return float(n & 16777215u) / 16777216.0;
}

int total_eyes() {
	return eye_count + (centre_eye ? 1 : 0);
}

vec2 eye_centre(int eye) {
	if (eye >= eye_count) {
		return vec2(0.0);
	}
	float a = TAU * (float(eye) / float(eye_count) + disc_rps * TIME);
	return vec2(cos(a), sin(a)) * ring_radius;
}

float eye_spin(int eye) {
	float speed = eye_rps * (1.0 + eye_rps_variance * (2.0 * rand(uint(eye) + 11u, 5u) - 1.0));
	if (alternate_spin && (eye % 2) == 1) {
		speed = -speed;
	}
	return speed;
}

void start() {
	uint seed = RANDOM_SEED + NUMBER * 7919u;
	int eye = int(floor(rand(seed, 1u) * float(total_eyes())));
	if (rand(seed, 4u) >= spawn_random) {
		eye = int(NUMBER % uint(total_eyes()));
	}
	eye = min(eye, total_eyes() - 1);
	float span = max(eye_radius - core_radius, 0.0);
	float r = core_radius + span * rand(seed, 2u);
	float a = TAU * rand(seed, 3u);
	CUSTOM = vec4(float(eye), 0.0, a, r);
	// Per-ball size lives in COLOR.a (unused by the additive source blend
	// once the portal stack reads luma), sampled once at spawn.
	COLOR = vec4(1.0, 1.0, 1.0, ball_scale * (1.0 + ball_scale_random * (2.0 * rand(seed, 5u) - 1.0)));
	TRANSFORM = mat4(1.0);
	TRANSFORM[3].xy = eye_centre(eye) + vec2(cos(a), sin(a)) * r;
	VELOCITY = vec3(0.0);
}

void process() {
	int eye = int(CUSTOM.x);
	float a = CUSTOM.z;
	float r = CUSTOM.w;
	float span = max(eye_radius - core_radius, 0.00001);
	float inward = 1.0 - clamp((r - core_radius) / span, 0.0, 1.0);
	float spin = eye_spin(eye);
	a += TAU * (spin + sign(spin) * eye_rps_differential * inward) * DELTA;
	r = clamp(r + drift * DELTA, core_radius, eye_radius);
	CUSTOM.z = a;
	CUSTOM.w = r;
	TRANSFORM[3].xy = eye_centre(eye) + vec2(cos(a), sin(a)) * r;

	// CUSTOM.y is the lifetime phase in [0, 1], same convention as
	// ParticleProcessMaterial. Grow in and shrink out so respawns do not
	// pop. Scale, not alpha: a half-alpha disc reads as mid luma across its
	// whole core, and the portal's edge band would paint the entire ball.
	CUSTOM.y = min(CUSTOM.y + DELTA / LIFETIME, 1.0);
	float t = CUSTOM.y;
	float grow = smoothstep(0.0, fade, t) * smoothstep(1.0, 1.0 - fade, t) * COLOR.a;
	TRANSFORM[0].xy = vec2(grow, 0.0);
	TRANSFORM[1].xy = vec2(0.0, grow);
}
