# Tutorial: writing `cell_borders_round` from nothing

Builds `generative/cell_borders_round` in seven steps. Every step is a complete
function that renders. Paste it into the `code` field of a scratch entry, add
the entry as a layer, look at the preview, then move on. The metadata side of a
`.tres` is not covered here.

Setup for the scratch entry: `kind_out = 0`, `coord = true`, `inputs = []`,
`params = []`, `depends = ["generative/hash"]`. Function name `scratch`. The
codegen calls it as `scratch(coord)` where `coord` is the layer's uv after the
coord block (scale, offset, rotation, scroll, warp) has been applied.

Reading rule for every step: a field is a picture of its iso-lines. Whatever
value the function returns, `smoothstep` downstream picks one iso-line and
makes it the visible edge. So the question at each step is "what shape are
the iso-lines", never "what color is it".

---

## Step 1. The grid

```glsl
float scratch(vec2 p) {
	vec2 cell = floor(p);
	vec2 local_f = fract(p);
	return local_f.x;
}
```

Preview: vertical sawtooth ramps, one per unit of `p`. Set the coord scale to
`8` to see eight of them.

- `floor(p)` is the integer cell id. Same value everywhere inside one cell.
- `fract(p)` is the position inside the cell, `0..1` on each axis.
- Every tiled generator in the library starts with these two lines. `checker`,
  `stripes`, `hash`, `voronoi`, all of them.

Try: return `local_f.y`, then `cell.x * 0.1`. The second one is flat steps,
one gray per column. That flat-per-cell property is what the next step uses.

## Step 2. One random point per cell

```glsl
float scratch(vec2 p) {
	vec2 cell = floor(p);
	vec2 local_f = fract(p);
	vec2 point = vec2(hash(cell), hash(cell + vec2(37.0, 17.0)));
	return point.x;
}
```

Preview: flat random gray per cell, a mosaic.

- `hash(cell)` returns a stable `0..1` number for a cell id. Same cell, same
  number, every frame. That is the whole reason random looks random here
  instead of flickering.
- Two calls with different inputs give two independent numbers, so `point` is
  a random position inside the cell. The `vec2(37.0, 17.0)` offset is only
  there to make the second call see a different input. Any constant works.
- `point` is in the same `0..1` space as `local_f`, so the two can be
  subtracted directly.

## Step 3. Distance to your own cell's point

```glsl
float scratch(vec2 p) {
	vec2 cell = floor(p);
	vec2 local_f = fract(p);
	vec2 point = vec2(hash(cell), hash(cell + vec2(37.0, 17.0)));
	return length(point - local_f);
}
```

Preview: a dark dot per cell with a radial ramp around it, and hard seams at
every cell boundary.

- `length(point - local_f)` is euclidean distance from the pixel to the point.
  Iso-lines of distance-to-a-point are circles. This is where "round" comes
  from, and it never goes away as long as the function returns a distance to
  a point.
- The seams are the bug this whole family of functions exists to fix. A pixel
  near the left edge of its cell is often closer to the point in the cell to
  its left, but this code only ever looks at its own cell's point.

## Step 4. Look at the neighbors (this is `voronoi`)

```glsl
float scratch(vec2 p) {
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
```

Preview: the seams are gone. Dark dots, smooth radial ramps, creases where
two ramps meet. This is `generative/voronoi` line for line.

- The loop visits the 3x3 block of cells centered on ours. `neighbor` is the
  cell offset, `-1..1` on each axis.
- `hash(cell + neighbor)` is that neighbor's point, computed the same way it
  computes it for itself, so both cells agree on where it is.
- `neighbor + point - local_f` converts the neighbor's point into our cell's
  local frame before subtracting. Without the `neighbor +` term the loop would
  measure nine points all imagined inside our own cell.
- `min_dist` starts at `1.0`, the largest distance that matters, and the loop
  keeps the smallest. The result is F1, distance to the nearest point.
- A 3x3 block is enough because a point can be anywhere in its own cell, so
  the nearest point is never more than one cell away.

This function measures distance to a point. Its iso-lines are circles. The
cell polygon only shows up as the crease where two circles meet, which is why
thresholding it gives touching balls and not tiles.

## Step 5. Keep the second nearest too (this is `cellular_edges`)

```glsl
float scratch(vec2 p) {
	vec2 cell = floor(p);
	vec2 local_f = fract(p);
	float f1 = 8.0;
	float f2 = 8.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 neighbor = vec2(float(x), float(y));
			vec2 point = vec2(hash(cell + neighbor), hash(cell + neighbor + vec2(37.0, 17.0)));
			vec2 diff = neighbor + point - local_f;
			float dist = length(diff);
			if (dist < f1) {
				f2 = f1;
				f1 = dist;
			} else if (dist < f2) {
				f2 = dist;
			}
		}
	}
	return f2 - f1;
}
```

Preview: black lines on the cell boundaries, brighter toward each center. No
dot at the center. This is `generative/cellular_edges`.

- Same loop. Instead of one running minimum it keeps the two smallest. When a
  new smaller distance arrives, the old smallest slides down to `f2`.
- On the boundary between two cells the pixel is equally far from both points,
  so `f1 == f2` and the difference is `0`. That is why the edges are exactly
  where the cells meet, with no seam bug.
- The center dot is gone because `f2 - f1` is not a distance to a point. At the
  point itself `f1 = 0` and the value is `f2`, which is large. The field peaks
  at the point instead of dipping.

Why it is only approximately edge distance: for two points, `f2 - f1` is `0`
on the bisector and grows as you move off it, but the growth rate depends on
where along the bisector you are. Near the midpoint between the points it
grows at twice the true distance. Far out toward a corner it grows slower.
Thresholding it gives edges that are thin in the middle and thicker at the
corners.

## Step 6. Exact edge distance (this is `cell_borders`)

Two changes. Pass one remembers which point was nearest. Pass two measures the
distance to the bisector between that point and every other point.

```glsl
float scratch(vec2 p) {
	vec2 cell = floor(p);
	vec2 local_f = fract(p);
	vec2 nearest_offset = vec2(0.0);
	vec2 nearest_rel = vec2(0.0);
	float nearest_dist_sq = 8.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 offset = vec2(float(x), float(y));
			vec2 point = vec2(hash(cell + offset), hash(cell + offset + vec2(37.0, 17.0)));
			vec2 rel = offset + point - local_f;
			float dist_sq = dot(rel, rel);
			if (dist_sq < nearest_dist_sq) {
				nearest_dist_sq = dist_sq;
				nearest_rel = rel;
				nearest_offset = offset;
			}
		}
	}
	float border_dist = 8.0;
	for (int y = -2; y <= 2; y++) {
		for (int x = -2; x <= 2; x++) {
			vec2 offset = nearest_offset + vec2(float(x), float(y));
			vec2 point = vec2(hash(cell + offset), hash(cell + offset + vec2(37.0, 17.0)));
			vec2 rel = offset + point - local_f;
			if (dot(nearest_rel - rel, nearest_rel - rel) > 0.00001) {
				border_dist = min(border_dist, dot(0.5 * (nearest_rel + rel), normalize(rel - nearest_rel)));
			}
		}
	}
	return border_dist;
}
```

Preview: same black boundary lines, but now the ramp away from the edge is
even everywhere. Thresholding gives constant-width edges and the interior
iso-lines are polygons shrunk inward.

Pass one:
- `dot(rel, rel)` is distance squared. Comparing squared distances avoids a
  `sqrt` per neighbor and gives the same winner.
- `nearest_rel` is the vector from the pixel to the nearest point.
  `nearest_offset` is which cell it lived in. Both are needed by pass two.

Pass two, the bisector math:
- Work in the pixel's frame: the pixel is at the origin, `a = nearest_rel`
  points to the nearest point, `b = rel` points to some other point.
- The bisector between `a` and `b` is the line through their midpoint,
  `0.5 * (a + b)`, perpendicular to `b - a`.
- Distance from the origin to a line through point `m` with unit normal `n`
  is `dot(m, n)`. So `dot(0.5 * (a + b), normalize(b - a))` is the distance
  from the pixel to that bisector. That is the whole formula.
- The min over every other point gives the distance to the nearest bisector,
  which is the nearest cell edge. Exact, no approximation.
- The `> 0.00001` guard skips the case where `rel` is the nearest point itself
  (offset `0,0` in the second loop). `normalize` of a zero vector is undefined.

Why 5x5 in pass two: the loop is centered on the nearest point's cell, not
ours, and the point that owns the edge nearest to us can be two cells away
from that one when jitter is high.

## Step 7. Round the corners (this is `cell_borders_round`)

One line changes. Replace the `min` in pass two with a smooth minimum, and
take `roundness` as a parameter.

```glsl
float scratch(vec2 p, float roundness) {
	// pass one unchanged from step 6
	...
	float border_dist = 8.0;
	for (int y = -2; y <= 2; y++) {
		for (int x = -2; x <= 2; x++) {
			vec2 offset = nearest_offset + vec2(float(x), float(y));
			vec2 point = vec2(hash(cell + offset), hash(cell + offset + vec2(37.0, 17.0)));
			vec2 rel = offset + point - local_f;
			if (dot(nearest_rel - rel, nearest_rel - rel) > 0.00001) {
				float d = dot(0.5 * (nearest_rel + rel), normalize(rel - nearest_rel));
				float h = clamp(0.5 + 0.5 * (border_dist - d) / roundness, 0.0, 1.0);
				border_dist = mix(border_dist, d, h) - roundness * h * (1.0 - h);
			}
		}
	}
	return max(border_dist, 0.0);
}
```

Add `roundness` to `params` as a float, `0.001..0.5`, default `0.15`. The
codegen appends params after the coord argument, in manifest order.

Preview: same cells, corners of every interior iso-line rounded. At
`roundness = 0.001` it matches step 6.

Smooth minimum, read line by line:
- `min(a, b)` has a crease where `a == b`. That crease is the polygon corner.
- `h` measures how close `a` and `b` are, on a `0..1` scale, over a window of
  width `2 * roundness`. Far apart on either side: `h` is `0` or `1` and
  `mix` returns whichever is smaller, same as `min`. Close together: `h` is
  in between and `mix` blends them.
- The blend alone would bulge outward at the crease. Subtracting
  `roundness * h * (1 - h)` pulls it back down. `h * (1 - h)` is a bump that
  is `0` at both ends and `0.25` in the middle, so the correction only acts
  inside the window.
- `max(border_dist, 0.0)` is needed because that correction can push the
  value slightly below the true minimum, which at the edge itself is `0`.
  Without the clamp the boundary goes faintly negative and `invert` downstream
  overshoots `1`.

That is the complete function. Everything in it is one of: `floor`/`fract`,
`hash`, a neighbor loop, a distance, `dot` against a normal, and `mix`.

---

## Other cell shapes

Which knob changes what, and whether it needs new code.

### Jitter (regular to random). New param, tiny change.

`point = vec2(0.5) + jitter * (point - vec2(0.5))` right after computing
`point`, in every loop. `jitter = 0` puts every point at its cell center: a
perfect square grid. `jitter = 1` is the current behavior. Values around
`0.5` give cells that are all roughly the same size, which is what cracked
mud, basalt columns, and cooled lava plates look like. This is the single
most useful missing param on all three entries. Backward compatible with
default `1.0`.

### Distance metric (round to diamond to square). New param, one line.

Replace `length(diff)` in steps 4 and 5:
- `abs(diff.x) + abs(diff.y)` manhattan: diamond-shaped cells.
- `max(abs(diff.x), abs(diff.y))` chebyshev: square cells with axis-aligned
  edges, looks like stone tiles.
- `pow(pow(abs(diff.x), k) + pow(abs(diff.y), k), 1.0 / k)` minkowski: `k = 1`
  manhattan, `k = 2` euclidean, `k` large approaches chebyshev. One float param
  covers all three.

This applies to `voronoi` and `cellular_edges` only. The bisector method in
step 6 assumes euclidean distance. Under manhattan the set of points
equidistant from two points is not a straight line, so `dot(m, n)` stops
being the edge distance.

### Grid layout (square to hex). Moderate change, step 1 only.

Offset every other row by half a cell before `floor`:
`p.x += 0.5 * mod(floor(p.y), 2.0)`. At `jitter = 0` this gives a hexagonal
tiling. At `jitter = 1` it is indistinguishable from the square grid, so it
only matters together with jitter.

### Weighted cells (different sizes). Small change, F1 family only.

Give each cell a random radius and subtract it:
`dist = length(diff) - hash(cell + offset + vec2(91.0, 53.0)) * weight`.
Big weights win more territory. Cells become different sizes with curved
edges. Real name: additively weighted Voronoi. Does not fit the bisector
method, edges are hyperbola arcs.

### Wobbly edges (domain warp). No code, exists today.

The coord block already has `warp_x` and `warp_y` slots and `warp_strength`.
Point both at a `generative/fbm` or `snoise` layer and raise the strength. The
grid is evaluated at a displaced position, so every straight edge picks up the
noise. For lava this is the change that matters most. Real cracks are not
straight and no amount of corner rounding fixes that.

### Two scales (plates with sub-cracks). No code, exists today.

Two `cell_borders` layers at different coord scales, `fieldops/min` of the
two. Big plates with fine cracks inside them.

### Smooth voronoi. New function, F1 only.

IQ's "smooth voronoi" replaces `min` over F1 with a weighted average,
`sum(dist * exp(-k * dist)) / sum(exp(-k * dist))`. Removes the creases
between cells and turns the field into soft blobs. It is a different thing
from rounded corners: it smooths the F1 cones, not the edge polygon. Useful
for metaballs, not for tiles.

## Does a different edge distance make lava better

No. Exact bisector distance is already the correct quantity for "distance to
the crack" and rounded corners are a cosmetic on top of it. The lava look
comes from three things that are not the distance formula:

1. Jitter around `0.5`, so the plates are similar in size.
2. Domain warp from fbm, so the cracks wander.
3. Two scales combined with `min`, so plates have fine cracks.

Two of the three exist in the tool now. Jitter is one param on the existing
entries and is the recommended next change.

---

# Part 2: two constructions of your own

Both start from the step 7 function as you wrote it, with your names:
`diff` for the tutorial's `rel`, `nearest_diff` for `nearest_rel`,
`nearest_neighbor` for `nearest_offset`, seed `vec2(19.0, 12.0)`, start
`10.0`. Every step is again a complete function that renders in the scratch
entry. Where the manifest needs a change beyond `code`, it is called out,
because without it the shader will not compile.

Reading rule carries over: a field is a picture of its iso-lines. Both steps
change the iso-lines near the edges and leave the interiors alone. That is
what makes them read as plates instead of blobs.

## Step 8. One corner radius per plate

The goal: every cell rounds its corners by a different amount. Big round
plates next to sharp small ones.

### 8a. Make the radius come from a hash

Start from step 7. Delete the `roundness` parameter from the signature and
compute it inside the function instead, right after pass one:

```glsl
float scratch(vec2 p) {
	vec2 cell = floor(p);
	vec2 local_fraction = fract(p);
	vec2 nearest_neighbor = vec2(0.0);
	vec2 nearest_diff = vec2(0.0);
	float nearest_dist_sq = 8.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 neighbor = vec2(float(x), float(y));
			vec2 point = vec2(hash(cell + neighbor), hash(cell + neighbor + vec2(19.0, 12.0)));
			vec2 diff = neighbor + point - local_fraction;
			float dist_sq = dot(diff, diff);
			if (dist_sq < nearest_dist_sq) {
				nearest_dist_sq = dist_sq;
				nearest_diff = diff;
				nearest_neighbor = neighbor;
			}
		}
	}
	float roundness = hash(cell + nearest_neighbor + vec2(91.0, 53.0)) * 0.5;
	float border_dist = 10.0;
	for (int y = -2; y <= 2; y++) {
		for (int x = -2; x <= 2; x++) {
			vec2 neighbor = nearest_neighbor + vec2(float(x), float(y));
			vec2 point = vec2(hash(cell + neighbor), hash(cell + neighbor + vec2(19.0, 12.0)));
			vec2 diff = neighbor + point - local_fraction;
			if (dot(nearest_diff - diff, nearest_diff - diff) > 0.00001) {
				float d = dot(0.5 * (nearest_diff + diff), normalize(diff - nearest_diff));
				float h = clamp(0.5 + 0.5 * (border_dist - d) / roundness, 0.0, 1.0);
				border_dist = mix(border_dist, d, h) - roundness * h * (1.0 - h);
			}
		}
	}
	return max(border_dist, 0.0);
}
```

Manifest: remove the `roundness` entry from `params`, since the function no
longer takes it. Signature and `params` must always agree, in order.

Preview at scale `4`: same plates as step 7, but some have sharp corners and
some are nearly circular.

The one new line:
- `hash(cell + nearest_neighbor + vec2(91.0, 53.0))` is a third random
  number for the cell. Same trick as the point: a different constant offset
  gives a different but stable number. `91, 53` is arbitrary, it only has to
  differ from `0,0` and `19,12`.
- `* 0.5` scales the `0..1` hash into `0..0.5`, the range the slider had.
- `roundness` is now a per-pixel local, but every pixel in the same plate
  computes the same value, so the plate has one radius.

### Why `cell + nearest_neighbor` and not `cell`

This is the part that matters. `cell` is the grid square the pixel is in.
`cell + nearest_neighbor` is the grid square whose point owns the pixel. They
differ whenever a plate crosses a grid line, which is most of the time.

Try `hash(cell + vec2(91.0, 53.0))` instead and look: plates get a visible
seam where they cross a grid line, because the radius changes mid-plate.
The plate is defined by the nearest point, so anything that is "per plate"
has to key off the nearest point's cell. `nearest_neighbor` was saved in pass
one for the 5x5 loop, and it is exactly the id you need here too.

### 8b. Put the range back on sliders

A fixed `0..0.5` is fine for looking. For a library entry the range should
be tunable, so take two params and blend between them:

```glsl
float scratch(vec2 p, float roundness_min, float roundness_max) {
	// pass one unchanged
	...
	float roundness = max(mix(roundness_min, roundness_max, hash(cell + nearest_neighbor + vec2(91.0, 53.0))), 0.001);
	// pass two unchanged
	...
	return max(border_dist, 0.0);
}
```

Manifest: two `float` params, `roundness_min` default `0.02` and
`roundness_max` default `0.3`, both `0.001..0.5`, in that order.

- `mix(a, b, t)` with `t` in `0..1` is `a + (b - a) * t`. With a hash as `t`
  it picks a random value between the two sliders.
- `max(..., 0.001)` guards the division `/ roundness` in pass two. If both
  sliders sat at `0` the shader would divide by zero. Never let a divisor
  reach zero, and put the guard where the divisor is made, not where it is
  used.
- Setting both sliders equal reproduces step 7. That is the check that
  nothing else changed.

That is `generative/cell_borders_round_varied`.

## Step 9. Wobbly cracks, still plates

The goal: the cracks between plates wander like real cracks, but the plate
interiors stay smooth. A plain domain warp bends everything. The trick is to
let the field decide where the warp is allowed.

This step does not modify the cell function. It wraps it. So the scratch
entry needs to be able to call `cell_borders` and `snoise`.

Manifest: `depends = Array[String](["generative/cell_borders", "generative/snoise"])`.
The codegen walks `depends` and pastes those functions into the shader before
yours, so the call resolves. `fbm` does exactly this with `snoise`. Without
the line, the compiler reports an undefined function.

### 9a. Plain domain warp, to see what is wrong with it

```glsl
float scratch(vec2 p, float warp_strength, float warp_scale) {
	vec2 q = p * warp_scale;
	vec2 noise = vec2(snoise(q), snoise(q + vec2(41.0, 23.0)));
	vec2 warped = p + noise * warp_strength;
	return cell_borders(warped);
}
```

Manifest: params `warp_strength` float `0..0.5` default `0.15`, and
`warp_scale` float `0.5..8` default `3.0`.

Preview at scale `4`: cracks wobble, and so does every iso-line inside every
plate. The plates look like they are underwater.

Line by line:
- `q = p * warp_scale` sets the noise frequency. `snoise` repeats about once
  per unit, so `warp_scale = 3` gives roughly three wobbles per cell.
- Two `snoise` calls with a constant offset make a `vec2`, the same trick as
  the point hash in step 2. Noise is a float field, a warp needs an x and a y.
  `41, 23` is arbitrary.
- `snoise` returns roughly `-1..1`, so `noise * warp_strength` displaces by up
  to `warp_strength` cells in either direction.
- `cell_borders(warped)` evaluates the whole two-pass function at the moved
  position. Nothing inside `cell_borders` knows it was moved. That is what a
  domain warp is: you lie to the function about where the pixel is.

### 9b. Gate the warp by the unwarped distance

```glsl
float scratch(vec2 p, float warp_strength, float warp_scale, float edge_band) {
	float unwarped = cell_borders(p);
	float weight = 1.0 - smoothstep(0.0, max(edge_band, 0.0001), unwarped);
	vec2 q = p * warp_scale;
	vec2 noise = vec2(snoise(q), snoise(q + vec2(41.0, 23.0)));
	vec2 warped = p + noise * warp_strength * weight;
	return cell_borders(warped);
}
```

Manifest: add `edge_band` float `0.01..1` default `0.25` as the third param.

Preview at scale `4`: cracks wobble, plate interiors are flat polygons again.
Set `edge_band` to `1.0` and it turns back into 9a. Set `warp_strength` to
`0` and it is plain `cell_borders`.

The two new lines:
- `unwarped = cell_borders(p)` asks the honest question first: how far is this
  pixel from a crack, before any warping. On a crack it is `0`.
- `weight = 1.0 - smoothstep(0.0, edge_band, unwarped)` turns that distance
  into a `0..1` amount. `smoothstep` ramps from `0` at the crack to `1` at
  `edge_band` away. `1.0 -` flips it, so the weight is `1` on the crack and
  `0` once you are `edge_band` deep into a plate. Between, a smooth ramp with
  no crease.
- `max(edge_band, 0.0001)` is the same zero guard as step 8. `smoothstep`
  with equal edges is undefined.
- `noise * warp_strength * weight` is the warp scaled by the weight. Deep in
  a plate the weight is `0` and `warped == p`, so the interior is evaluated
  at its true position and stays flat. Near a crack the full warp applies.

Why this is a feedback term: the output of `cell_borders` decides the input
to `cell_borders`. The field is consulted about itself. It only works because
the first call is at the true `p`, so the answer is stable and there is no
loop to converge. One extra evaluation of `cell_borders` per pixel is the
whole cost.

That is `generative/cell_borders_edge_warp`.

### Swapping the inner function

9b calls `cell_borders`. Nothing requires that. Change both calls to
`cell_borders_round_varied(p, 0.02, 0.3)` and the `depends` entry to match,
and the plates have per-cell rounded corners and wobbly cracks at once. Or
call your own scratch step 7 by its function name. The wrapper does not care
what it wraps, as long as the thing returns `0` on the crack.

## What you own after part 2

- Step 8 is a hash keyed off `nearest_neighbor` instead of a slider. The
  bisector method is IQ's. The per-plate radius is not published as a named
  technique anywhere I could find. Unverified beyond that search.
- Step 9 is a domain warp gated by the field's own unwarped value. Domain
  warping is IQ's article. Gating it by edge distance so only cracks move is
  the construction here.
- Both manifests say so in `source_math`, with today's date. `source_code_url`
  is empty because nothing was ported. That is the honest record: technique
  cited, combination claimed, code written here.
