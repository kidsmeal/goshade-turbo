// GoShade Turbo generated shader. MIT License.
// stack: {"coord_space":"uv","layers":[{"coord":null,"entry":"source/texture","id":"0","kind_out":1,"params":{},"slots":{}},{"coord":{"offset":[0.0,0.0],"rotation":0.0,"scale":[3.0,3.0],"scroll":[0.150000005960464,0.0500000007450581],"warp_strength":0.0,"warp_x":"","warp_y":""},"entry":"generative/snoise","id":"1","kind_out":0,"params":{},"slots":{}},{"coord":{"offset":[-1.0,0.0],"rotation":-1.5707963267949,"scale":[2.0,2.0],"scroll":[0.0,0.0],"warp_strength":0.12,"warp_x":"1","warp_y":""},"entry":"generative/linear_gradient","id":"2","kind_out":0,"params":{},"slots":{}},{"coord":null,"entry":"color/palette","id":"3","kind_out":1,"params":{"a":[0.150000005960464,0.709999978542328,0.649999976158142],"b":[0.519999980926514,0.490000009536743,0.159999996423721],"c":[0.920000016689301,0.370000004768372,0.829999983310699],"d":[0.819999992847443,0.0900000035762787,0.479999989271164]},"slots":{"t":"2"}},{"coord":{"offset":[0.0,0.0],"rotation":-1.5707963267949,"scale":[48.0,48.0],"scroll":[0.0,0.0],"warp_strength":0.0,"warp_x":"","warp_y":""},"entry":"generative/stripes","id":"4","kind_out":0,"params":{},"slots":{}},{"coord":null,"entry":"color/gradient_map","id":"5","kind_out":1,"params":{"color_a":[0.600000023841858,0.600000023841858,0.649999976158142,1.0],"color_b":[1.0,1.0,1.0,1.0]},"slots":{"t":"4"}},{"coord":null,"entry":"color/multiply","id":"6","kind_out":1,"params":{"t":0.5},"slots":{"a":"3","b":"5"}},{"coord":null,"entry":"filter/outline","id":"7","kind_out":1,"params":{"thickness":0.006,"threshold":0.1},"slots":{"source":"0"}},{"coord":null,"entry":"color/fill","id":"8","kind_out":1,"params":{"color":[0.0199999995529652,0.0500000007450581,0.119999997317791,1.0]},"slots":{}},{"coord":null,"entry":"color/mix","id":"9","kind_out":1,"params":{},"slots":{"a":"6","b":"8","mask":"7"}},{"coord":null,"entry":"fieldops/alpha","id":"10","kind_out":0,"params":{},"slots":{"color":"0"}},{"coord":null,"entry":"fieldops/max","id":"11","kind_out":0,"params":{},"slots":{"a":"10","b":"7"}}],"next_id":12,"output_alpha":"11","output_color":"9","schema":1}
shader_type canvas_item;

group_uniforms L01_snoise;
uniform vec2 l1_scale = vec2(3.0, 3.0);
uniform vec2 l1_offset = vec2(0.0, 0.0);
uniform float l1_rotation = 0.0;
uniform vec2 l1_scroll = vec2(0.15000000596046, 0.05000000074506);
group_uniforms L02_linear_gradient;
uniform vec2 l2_scale = vec2(2.0, 2.0);
uniform vec2 l2_offset = vec2(-1.0, 0.0);
uniform float l2_rotation = -1.5707963267949;
uniform float l2_warp_strength = 0.12;
group_uniforms L03_palette;
uniform vec3 l3_palette_a = vec3(0.15000000596046, 0.70999997854233, 0.64999997615814);
uniform vec3 l3_palette_b = vec3(0.51999998092651, 0.49000000953674, 0.15999999642372);
uniform vec3 l3_palette_c = vec3(0.9200000166893, 0.37000000476837, 0.8299999833107);
uniform vec3 l3_palette_d = vec3(0.81999999284744, 0.09000000357628, 0.47999998927116);
group_uniforms L04_stripes;
uniform vec2 l4_scale = vec2(48.0, 48.0);
uniform vec2 l4_offset = vec2(0.0, 0.0);
uniform float l4_rotation = -1.5707963267949;
group_uniforms L05_gradient_map;
uniform vec4 l5_gradient_map_color_a : source_color = vec4(0.60000002384186, 0.60000002384186, 0.64999997615814, 1.0);
uniform vec4 l5_gradient_map_color_b : source_color = vec4(1.0, 1.0, 1.0, 1.0);
group_uniforms L06_color_multiply;
uniform float l6_color_multiply_t : hint_range(0.0, 1.0) = 0.5;
group_uniforms L07_outline;
uniform float l7_outline_thickness : hint_range(0.0005, 0.02) = 0.006;
uniform float l7_outline_threshold : hint_range(0.0, 1.0) = 0.1;
group_uniforms L08_fill;
uniform vec4 l8_fill_color : source_color = vec4(0.01999999955297, 0.05000000074506, 0.11999999731779, 1.0);

vec2 gst_transform(vec2 p, vec2 scale, float rotation, vec2 offset) {
	vec2 scaled = p * scale;
	float s = sin(rotation);
	float c = cos(rotation);
	vec2 rotated = vec2(scaled.x * c - scaled.y * s, scaled.x * s + scaled.y * c);
	return rotated + offset;
}


float luma(vec4 c) {
	return dot(c.rgb, vec3(0.299, 0.587, 0.114));
}


float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453123);
}

vec2 gst_grad2(ivec2 i) {
	float a = hash(vec2(i)) * 6.28318530718;
	return vec2(cos(a), sin(a));
}

float snoise(vec2 p) {
	const float k1 = 0.36602540378; // (sqrt(3.0) - 1.0) / 2.0
	const float k2 = 0.21132486541; // (3.0 - sqrt(3.0)) / 6.0
	vec2 i = floor(p + (p.x + p.y) * k1);
	vec2 a = p - i + (i.x + i.y) * k2;
	vec2 o = a.x > a.y ? vec2(1.0, 0.0) : vec2(0.0, 1.0);
	vec2 b = a - o + k2;
	vec2 c = a - 1.0 + 2.0 * k2;
	vec3 h = max(0.5 - vec3(dot(a, a), dot(b, b), dot(c, c)), 0.0);
	// Integer corner addresses keep shared gradients consistent across renderers.
	vec3 n = h * h * h * h * vec3(dot(a, gst_grad2(ivec2(i))), dot(b, gst_grad2(ivec2(i) + ivec2(o))), dot(c, gst_grad2(ivec2(i) + ivec2(1))));
	return dot(n, vec3(70.0));
}

float linear_gradient(vec2 p) {
	return clamp(p.x + 0.5, 0.0, 1.0);
}

vec4 palette(float t, vec3 a, vec3 b, vec3 c, vec3 d) {
	vec3 rgb = a + b * cos(6.28318530718 * (c * t + d));
	return vec4(rgb, 1.0);
}

float stripes(vec2 p) {
	return 0.5 + 0.5 * sin(p.x * 6.28318530718);
}

vec4 gradient_map(float t, vec4 color_a, vec4 color_b) {
	return mix(color_a, color_b, clamp(t, 0.0, 1.0));
}

vec4 color_multiply(vec4 a, vec4 b, float t) {
	vec4 blended = vec4(a.rgb * b.rgb, a.a);
	return mix(a, blended, t);
}

vec4 fill(vec4 color) {
	return color;
}

vec4 color_mix(vec4 a, vec4 b, float mask) {
	return mix(a, b, mask);
}

float alpha(vec4 color) {
	return color.a;
}

float gst_max(float a, float b) {
	return max(a, b);
}

void fragment() {
	vec2 space_coord = UV;
	vec4 l0 = texture(TEXTURE, space_coord);
	vec2 coord1 = gst_transform(space_coord, l1_scale, l1_rotation, l1_offset);
	coord1 += l1_scroll * TIME;
	float l1 = snoise(coord1);
	vec2 coord2 = gst_transform(space_coord, l2_scale, l2_rotation, l2_offset);
	coord2 += vec2(l1, 0.0) * l2_warp_strength;
	float l2 = linear_gradient(coord2);
	vec4 l3 = palette(l2, l3_palette_a, l3_palette_b, l3_palette_c, l3_palette_d);
	vec2 coord4 = gst_transform(space_coord, l4_scale, l4_rotation, l4_offset);
	float l4 = stripes(coord4);
	vec4 l5 = gradient_map(l4, l5_gradient_map_color_a, l5_gradient_map_color_b);
	vec4 l6 = color_multiply(l3, l5, l6_color_multiply_t);
	vec4 l7;
	{
		float center_a = texture(TEXTURE, UV).a;
		float neighbor_a = max(
			max(texture(TEXTURE, UV + vec2(l7_outline_thickness, 0.0)).a, texture(TEXTURE, UV - vec2(l7_outline_thickness, 0.0)).a),
			max(texture(TEXTURE, UV + vec2(0.0, l7_outline_thickness)).a, texture(TEXTURE, UV - vec2(0.0, l7_outline_thickness)).a)
		);
		float edge = step(l7_outline_threshold, neighbor_a - center_a);
		l7 = vec4(vec3(edge), edge);
	}
	vec4 l8 = fill(l8_fill_color);
	vec4 l9 = color_mix(l6, l8, luma(l7));
	float l10 = alpha(l0);
	float l11 = gst_max(l10, luma(l7));
	COLOR = vec4(l9.rgb, l11);
}
