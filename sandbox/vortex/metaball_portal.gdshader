// GoShade Turbo generated shader. MIT License.
// stack: {"coord_space":"uv","layers":[{"coord":null,"entry":"source/texture","id":"0","kind_out":1,"params":{},"slots":{}},{"coord":null,"entry":"fieldops/smoothstep","id":"1","kind_out":0,"params":{"edge0":0.3,"edge1":0.5},"slots":{"x":"0"}},{"coord":null,"entry":"color/fill","id":"11","kind_out":1,"params":{"color":[0.860914051532745,0.456958115100861,0.717395544052124,1.0]},"slots":{}},{"coord":null,"entry":"fieldops/smoothstep","id":"12","kind_out":0,"params":{"edge0":0.6,"edge1":0.68},"slots":{"x":"0"}},{"coord":null,"entry":"fieldops/invert","id":"13","kind_out":0,"params":{},"slots":{"x":"12"}},{"coord":null,"entry":"fieldops/multiply","id":"14","kind_out":0,"params":{},"slots":{"a":"1","b":"13"}},{"coord":{"offset":[0.0,0.0],"rotation":1.01499999999942,"scale":[1.0,1.0],"scroll":[0.25,0.0],"warp_strength":0.0,"warp_x":"","warp_y":""},"entry":"generative/stripes","id":"3","kind_out":0,"params":{},"slots":{}},{"coord":null,"entry":"color/palette","id":"4","kind_out":1,"params":{"a":[0.5,0.300000011920929,0.600000023841858],"b":[0.5,0.400000005960464,0.5],"c":[1.0,1.0,1.0],"d":[0.0,0.200000002980232,0.400000005960464]},"slots":{"t":"3"}},{"coord":{"offset":[0.0,0.0],"rotation":0.0,"scale":[12.0,12.0],"scroll":[0.100000001490116,0.100000001490116],"warp_strength":0.0,"warp_x":"","warp_y":""},"entry":"generative/voronoi","id":"5","kind_out":0,"params":{},"slots":{}},{"coord":null,"entry":"fieldops/smoothstep","id":"6","kind_out":0,"params":{"edge0":0.02,"edge1":0.12},"slots":{"x":"5"}},{"coord":null,"entry":"fieldops/invert","id":"7","kind_out":0,"params":{},"slots":{"x":"6"}},{"coord":null,"entry":"color/gradient_map","id":"8","kind_out":1,"params":{"color_a":[0.0,0.0,0.0500000007450581,1.0],"color_b":[1.0,1.0,0.899999976158142,1.0]},"slots":{"t":"7"}},{"coord":null,"entry":"color/hue_shift","id":"16","kind_out":1,"params":{"shift":0.0},"slots":{"color":"8"}},{"coord":null,"entry":"color/mix","id":"9","kind_out":1,"params":{},"slots":{"a":"16","b":"8","mask":"7"}},{"coord":null,"entry":"color/mix","id":"10","kind_out":1,"params":{},"slots":{"a":"9","b":"4","mask":"14"}}],"next_id":18,"output_alpha":"1","output_color":"10","schema":1}
shader_type canvas_item;

group_uniforms L01_gst_smoothstep;
uniform float l1_gst_smoothstep_edge0 : hint_range(-1.0, 2.0) = 0.3;
uniform float l1_gst_smoothstep_edge1 : hint_range(-1.0, 2.0) = 0.5;
group_uniforms L02_fill;
uniform vec4 l11_fill_color : source_color = vec4(0.86091405153275, 0.45695811510086, 0.71739554405212, 1.0);
group_uniforms L03_gst_smoothstep;
uniform float l12_gst_smoothstep_edge0 : hint_range(-1.0, 2.0) = 0.6;
uniform float l12_gst_smoothstep_edge1 : hint_range(-1.0, 2.0) = 0.68;
group_uniforms L06_stripes;
uniform vec2 l3_scale = vec2(1.0, 1.0);
uniform vec2 l3_offset = vec2(0.0, 0.0);
uniform float l3_rotation = 1.01499999999942;
uniform vec2 l3_scroll = vec2(0.25, 0.0);
group_uniforms L07_palette;
uniform vec3 l4_palette_a = vec3(0.5, 0.30000001192093, 0.60000002384186);
uniform vec3 l4_palette_b = vec3(0.5, 0.40000000596046, 0.5);
uniform vec3 l4_palette_c = vec3(1.0, 1.0, 1.0);
uniform vec3 l4_palette_d = vec3(0.0, 0.20000000298023, 0.40000000596046);
group_uniforms L08_voronoi;
uniform vec2 l5_scale = vec2(12.0, 12.0);
uniform vec2 l5_offset = vec2(0.0, 0.0);
uniform float l5_rotation = 0.0;
uniform vec2 l5_scroll = vec2(0.10000000149012, 0.10000000149012);
group_uniforms L09_gst_smoothstep;
uniform float l6_gst_smoothstep_edge0 : hint_range(-1.0, 2.0) = 0.02;
uniform float l6_gst_smoothstep_edge1 : hint_range(-1.0, 2.0) = 0.12;
group_uniforms L11_gradient_map;
uniform vec4 l8_gradient_map_color_a : source_color = vec4(0.0, 0.0, 0.05000000074506, 1.0);
uniform vec4 l8_gradient_map_color_b : source_color = vec4(1.0, 1.0, 0.89999997615814, 1.0);
group_uniforms L12_hue_shift;
uniform float l16_hue_shift_shift : hint_range(-1.0, 1.0) = 0.0;

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


float gst_smoothstep(float x, float edge0, float edge1) {
	// Equal or reversed edges: clamp edge1 above edge0 so GLSL smoothstep
	// (undefined for edge0 >= edge1) instead resolves to a step at edge0.
	float e1 = max(edge1, edge0 + 0.00001);
	return smoothstep(edge0, e1, x);
}

vec4 fill(vec4 color) {
	return color;
}

float invert(float x) {
	return 1.0 - x;
}

float multiply(float a, float b) {
	return a * b;
}

float stripes(vec2 p) {
	return 0.5 + 0.5 * sin(p.x * 6.28318530718);
}

vec4 palette(float t, vec3 a, vec3 b, vec3 c, vec3 d) {
	vec3 rgb = a + b * cos(6.28318530718 * (c * t + d));
	return vec4(rgb, 1.0);
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453123);
}

float voronoi(vec2 p) {
	vec2 cell = floor(p);
	vec2 local_f = fract(p);
	float min_dist = 1.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 neighbor = vec2(float(x), float(y));
			vec2 point = vec2(hash(cell + neighbor), hash(cell + neighbor + vec2(37.0, 17.0)));
			vec2 diff = neighbor + point - local_f;
			min_dist = min(min_dist, length(diff));
		}
	}
	return min_dist;
}

vec4 gradient_map(float t, vec4 color_a, vec4 color_b) {
	return mix(color_a, color_b, clamp(t, 0.0, 1.0));
}

vec4 hue_shift(vec4 color, float shift) {
	mat3 rgb2yiq = mat3(vec3(0.299, 0.596, 0.211), vec3(0.587, -0.274, -0.523), vec3(0.114, -0.322, 0.312));
	mat3 yiq2rgb = mat3(vec3(1.0, 1.0, 1.0), vec3(0.956, -0.272, -1.106), vec3(0.621, -0.647, 1.703));
	vec3 yiq = rgb2yiq * color.rgb;
	float angle = shift * 6.28318530718;
	float s = sin(angle);
	float c = cos(angle);
	vec2 rotated_iq = mat2(vec2(c, s), vec2(-s, c)) * yiq.yz;
	vec3 rgb = yiq2rgb * vec3(yiq.x, rotated_iq);
	return vec4(clamp(rgb, 0.0, 1.0), color.a);
}

vec4 color_mix(vec4 a, vec4 b, float mask) {
	return mix(a, b, mask);
}

void fragment() {
	vec2 space_coord = UV;
	vec4 l0 = texture(TEXTURE, space_coord);
	float l1 = gst_smoothstep(luma(l0), l1_gst_smoothstep_edge0, l1_gst_smoothstep_edge1);
	vec4 l11 = fill(l11_fill_color);
	float l12 = gst_smoothstep(luma(l0), l12_gst_smoothstep_edge0, l12_gst_smoothstep_edge1);
	float l13 = invert(l12);
	float l14 = multiply(l1, l13);
	vec2 coord3 = gst_transform(space_coord, l3_scale, l3_rotation, l3_offset);
	coord3 += l3_scroll * TIME;
	float l3 = stripes(coord3);
	vec4 l4 = palette(l3, l4_palette_a, l4_palette_b, l4_palette_c, l4_palette_d);
	vec2 coord5 = gst_transform(space_coord, l5_scale, l5_rotation, l5_offset);
	coord5 += l5_scroll * TIME;
	float l5 = voronoi(coord5);
	float l6 = gst_smoothstep(l5, l6_gst_smoothstep_edge0, l6_gst_smoothstep_edge1);
	float l7 = invert(l6);
	vec4 l8 = gradient_map(l7, l8_gradient_map_color_a, l8_gradient_map_color_b);
	vec4 l16 = hue_shift(l8, l16_hue_shift_shift);
	vec4 l9 = color_mix(l16, l8, l7);
	vec4 l10 = color_mix(l9, l4, l14);
	COLOR = vec4(l10.rgb, l1);
}
