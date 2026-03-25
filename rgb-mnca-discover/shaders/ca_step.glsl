#[compute]
#version 450

layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;

const int MAX_RADIUS = 12;
const int LOCAL_SIZE_X = 16;
const int LOCAL_SIZE_Y = 16;
const int TILE_W = LOCAL_SIZE_X + MAX_RADIUS * 2;
const int TILE_H = LOCAL_SIZE_Y + MAX_RADIUS * 2;
const int TILE_PIXELS = TILE_W * TILE_H;
const int WG_THREADS = LOCAL_SIZE_X * LOCAL_SIZE_Y;
const int CANDIDATE_COUNT = 4;
const int NEIGHBORHOODS_PER_CANDIDATE = 2;
const int RULE_CHANNEL_VALUES = 6;
const int MAX_RING_OFFSETS = 488;
const int DEAD_EDGE_SHADOW_STEPS = 4;
const uint RING_MASK_U12 = 0xFFFu;
const bool EDGE_PUSH_ENABLED = false;
const vec3 DEAD_VISUAL_RGB = vec3(0.58);
const float DEAD_EDGE_SHADOW_STRENGTH = 0.48;
const float DEAD_FADE_ALPHA_START = 0.45;
const float DEAD_FADE_ALPHA_STEP = 0.01;

layout(set = 0, binding = 0, rgba8) uniform readonly image2D src;
layout(set = 0, binding = 1, rgba8) uniform writeonly image2D dst;

// Offsets for all rings concatenated
layout(set = 0, binding = 2, std430) readonly buffer Offsets {
    ivec2 off[];
} offsets;

// Per-ring ranges into offsets.off[]
layout(set = 0, binding = 3, std430) readonly buffer RingParams {
    int base[12];
    int count[12];
} ring_params;

// Random thresholds (dvmd[32]) provided by CPU
layout(set = 0, binding = 4, std430) readonly buffer Thresholds {
    uint dvmd[32];
} T;

layout(set = 0, binding = 5, std430) readonly buffer Neighborhoods {
    uint nh[8];
} N;

layout(set = 0, binding = 6, std430) readonly buffer Brush {
    ivec4 brush_i;
    vec4  brush_f;
} B;

layout(set = 0, binding = 7, std430) readonly buffer CandidateMask {
    ivec4 enabled;
} C;

layout(set = 0, binding = 8, std430) readonly buffer BlendParams {
    vec4 blend;
} BK;

layout(set = 0, binding = 9, std430) readonly buffer RuleWeights {
    uint w[16];
} WG;

layout(set = 0, binding = 10, std430) readonly buffer NeighborhoodDistribution {
    uint counts[4];
} ND;

layout(set = 0, binding = 11, std430) readonly buffer RuleChannels {
    float triplets[96];
} CH;

// ---------- helpers ----------

ivec2 wrap_pos_fast(ivec2 p, ivec2 size) {
    while (p.x < 0) {
        p.x += size.x;
    }
    while (p.x >= size.x) {
        p.x -= size.x;
    }
    while (p.y < 0) {
        p.y += size.y;
    }
    while (p.y >= size.y) {
        p.y -= size.y;
    }
    return p;
}

ivec2 clamp_pos_fast(ivec2 p, ivec2 size) {
    return clamp(p, ivec2(0), size - ivec2(1));
}

vec2 wrap_delta(vec2 from_pos, vec2 to_pos, ivec2 size) {
    vec2 size_f = vec2(size);
    vec2 d = from_pos - to_pos;
    // Shortest toroidal vector from center to this pixel
    d -= round(d / size_f) * size_f;
    return d;
}

uint sample_packed_rgba(ivec2 p) {
    return packUnorm4x8(imageLoad(src, p));
}

vec3 unpack_rgb(uint packed) {
    return unpackUnorm4x8(packed).rgb;
}

vec3 unpack_rgb_alive(uint packed) {
    vec4 c = unpackUnorm4x8(packed);
    if (c.a < 0.5) {
        return vec3(0.0);
    }
    return c.rgb;
}

vec3 sample_rgb_bilinear(vec2 pos, ivec2 size) {
    vec2 base_f = floor(pos);
    ivec2 base = ivec2(base_f);
    vec2 frac_uv = fract(pos);

    ivec2 p00 = wrap_pos_fast(base, size);
    ivec2 p10 = wrap_pos_fast(base + ivec2(1, 0), size);
    ivec2 p01 = wrap_pos_fast(base + ivec2(0, 1), size);
    ivec2 p11 = wrap_pos_fast(base + ivec2(1, 1), size);

    vec3 c00 = unpack_rgb_alive(sample_packed_rgba(p00));
    vec3 c10 = unpack_rgb_alive(sample_packed_rgba(p10));
    vec3 c01 = unpack_rgb_alive(sample_packed_rgba(p01));
    vec3 c11 = unpack_rgb_alive(sample_packed_rgba(p11));

    vec3 cx0 = mix(c00, c10, frac_uv.x);
    vec3 cx1 = mix(c01, c11, frac_uv.x);
    return mix(cx0, cx1, frac_uv.y);
}

vec3 sample_rgb_bilinear_clamped(vec2 pos, ivec2 size) {
    vec2 base_f = floor(pos);
    ivec2 base = ivec2(base_f);
    vec2 frac_uv = fract(pos);

    ivec2 p00 = clamp_pos_fast(base, size);
    ivec2 p10 = clamp_pos_fast(base + ivec2(1, 0), size);
    ivec2 p01 = clamp_pos_fast(base + ivec2(0, 1), size);
    ivec2 p11 = clamp_pos_fast(base + ivec2(1, 1), size);

    vec3 c00 = unpack_rgb_alive(sample_packed_rgba(p00));
    vec3 c10 = unpack_rgb_alive(sample_packed_rgba(p10));
    vec3 c01 = unpack_rgb_alive(sample_packed_rgba(p01));
    vec3 c11 = unpack_rgb_alive(sample_packed_rgba(p11));

    vec3 cx0 = mix(c00, c10, frac_uv.x);
    vec3 cx1 = mix(c01, c11, frac_uv.x);
    return mix(cx0, cx1, frac_uv.y);
}

float sd_rounded_box(vec2 p, vec2 b, float r) {
    vec2 q = abs(p) - (b - vec2(r));
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

float sd_equilateral_triangle(vec2 p) {
    const float k = 1.73205080757;
    p.x = abs(p.x) - 1.0;
    p.y = p.y + 1.0 / k;
    if (p.x + k * p.y > 0.0) {
        p = vec2(p.x - k * p.y, -k * p.x - p.y) * 0.5;
    }
    p.x -= clamp(p.x, -2.0, 0.0);
    return -length(p) * sign(p.y);
}

float decode_unit_u8(uint v) {
    return float(v & 0xFFu) / 255.0;
}

float decode_weight_u8(uint v) {
    return decode_unit_u8(v) * 2.0 - 1.0;
}

vec3 hsv_to_rgb(vec3 hsv) {
    vec3 rgb = clamp(abs(mod(hsv.x * 6.0 + vec3(0.0, 4.0, 2.0), 6.0) - 3.0) - 1.0, 0.0, 1.0);
    return hsv.z * mix(vec3(1.0), rgb, hsv.y);
}

uint decode_ring_mask_u12(uint v) {
    return v & RING_MASK_U12;
}

vec3 read_triplet_for_rule(int rule_i) {
    // Triplets are pre-normalized on CPU before upload
    int base = rule_i * RULE_CHANNEL_VALUES;
    return vec3(
        CH.triplets[base + 0],
        CH.triplets[base + 1],
        CH.triplets[base + 2]
    );
}

vec3 write_triplet_for_rule(int rule_i) {
    // Triplets are pre-normalized on CPU before upload
    int base = rule_i * RULE_CHANNEL_VALUES;
    return vec3(
        CH.triplets[base + 3],
        CH.triplets[base + 4],
        CH.triplets[base + 5]
    );
}

shared uint s_tile[TILE_H][TILE_W];
shared ivec2 s_ring_offsets[MAX_RING_OFFSETS];

float dead_union_edge_shadow(ivec2 p_local) {
    const ivec2 dirs[8] = ivec2[8](
        ivec2(1, 0), ivec2(-1, 0), ivec2(0, 1), ivec2(0, -1),
        ivec2(1, 1), ivec2(1, -1), ivec2(-1, 1), ivec2(-1, -1)
    );
    float nearest_step = float(DEAD_EDGE_SHADOW_STEPS + 1);
    for (int step_i = 1; step_i <= DEAD_EDGE_SHADOW_STEPS; step_i++) {
        bool found_alive = false;
        for (int d = 0; d < 8; d++) {
            ivec2 q = p_local + dirs[d] * step_i;
            float qa = unpackUnorm4x8(s_tile[q.y][q.x]).a;
            if (qa >= 0.5) {
                found_alive = true;
                break;
            }
        }
        if (found_alive) {
            nearest_step = float(step_i);
            break;
        }
    }
    if (nearest_step > float(DEAD_EDGE_SHADOW_STEPS)) {
        return 0.0;
    }
    float inward = 1.0 - ((nearest_step - 1.0) / float(DEAD_EDGE_SHADOW_STEPS));
    return smoothstep(0.0, 1.0, inward);
}

void main() {
    ivec2 size = imageSize(src);

    ivec2 wg_origin = ivec2(gl_WorkGroupID.xy) * ivec2(LOCAL_SIZE_X, LOCAL_SIZE_Y);
    ivec2 tile_origin = wg_origin - ivec2(MAX_RADIUS);
    ivec2 lid2 = ivec2(gl_LocalInvocationID.xy);
    int lid = lid2.y * LOCAL_SIZE_X + lid2.x;

    for (int idx = lid; idx < TILE_PIXELS; idx += WG_THREADS) {
        int tx = idx % TILE_W;
        int ty = idx / TILE_W;
        ivec2 g = EDGE_PUSH_ENABLED
            ? clamp_pos_fast(tile_origin + ivec2(tx, ty), size)
            : wrap_pos_fast(tile_origin + ivec2(tx, ty), size);
        s_tile[ty][tx] = sample_packed_rgba(g);
    }
    int ring_offset_count = ring_params.base[MAX_RADIUS - 1] + ring_params.count[MAX_RADIUS - 1];
    ring_offset_count = clamp(ring_offset_count, 0, MAX_RING_OFFSETS);
    for (int idx = lid; idx < ring_offset_count; idx += WG_THREADS) {
        s_ring_offsets[idx] = offsets.off[idx];
    }
    barrier();

    ivec2 p = ivec2(gl_GlobalInvocationID.xy);
    if (p.x >= size.x || p.y >= size.y) {
        return;
    }

    ivec2 p_local = lid2 + ivec2(MAX_RADIUS);
    vec4 src_rgba = unpackUnorm4x8(s_tile[p_local.y][p_local.x]);
    vec3 res_rgb = src_rgba.rgb;
    float res_a = src_rgba.a;
    bool newly_dead_this_frame = false;

    if (B.brush_i.x != 0) { // active
        ivec2 c = ivec2(B.brush_i.z, B.brush_i.w);
        float radius   = B.brush_f.x;
        float strength = B.brush_f.y; // 0..1-ish

        // Safety
        radius   = max(radius, 0.0001);
        strength = clamp(strength, 0.0, 1.0);

        // In edge-push mode brush uses non-wrapping distance/sampling.
        vec2 dp = EDGE_PUSH_ENABLED ? (vec2(p) - vec2(c)) : wrap_delta(vec2(p), vec2(c), size);
        float d = length(dp);

        int brush_mode = B.brush_i.y; // 1 = paint, 2 = erase, 3 = expel, 4 = vacuum, 5 = dead-shape
        float mode_radius = radius;
        if (brush_mode == 4) {
            mode_radius = radius * 2.0;
        } else if (brush_mode == 3) {
            mode_radius = radius * 2.0;
        }

        if (brush_mode == 5) {
            float half_extent = max(mode_radius, 1.0);
            float angle = B.brush_f.w;
            float ca = cos(angle);
            float sa = sin(angle);
            vec2 q = vec2(
                ca * dp.x + sa * dp.y,
                -sa * dp.x + ca * dp.y
            );
            float corner_r = max(0.9, half_extent * 0.14);
            float sdf = 0.0;
            if (B.brush_f.z > 0.5) {
                float tri_scale = max(half_extent, 1.0);
                sdf = sd_equilateral_triangle(q / tri_scale) * tri_scale - corner_r;
            } else {
                sdf = sd_rounded_box(q, vec2(half_extent), corner_r);
            }
            if (sdf <= 0.0) {
                // Dead-zone visuals are resolved in a separate union-border pass below.
                // Here we only mark newly dead pixels and start a brief fade-in timer.
                if (src_rgba.a >= 0.5) {
                    res_a = DEAD_FADE_ALPHA_START;
                    newly_dead_this_frame = true;
                }
            }
        } else if (res_a >= 0.5 && d <= mode_radius) {
            float falloff = 0.0;
            if (brush_mode == 4) {
                // Donut-shaped vacuum: smooth bell-shaped annulus profile
                float inner_radius = mode_radius / 300.0;
                float ring_width = max(mode_radius - inner_radius, 0.0001);
                float edge_soft = clamp(ring_width * 0.30, 1.5, ring_width * 0.55);
                // Densest annulus is biased outward due to larger circumference
                float peak_radius = inner_radius + ring_width * 0.68;
                float sigma = max(ring_width * 0.34, 0.0001);
                float z = (d - peak_radius) / sigma;
                float gaussian = exp(-0.5 * z * z);
                float band_u = clamp((d - inner_radius) / ring_width, 0.0, 1.0);
                float sine_band = sin(3.14159265 * band_u);
                float inner_fade = smoothstep(inner_radius, inner_radius + edge_soft, d);
                float outer_fade = 1.0 - smoothstep(mode_radius - edge_soft, mode_radius, d);
                falloff = gaussian * sine_band * inner_fade * outer_fade;
            } else if (brush_mode == 3) {
                // Expel brush: smooth cosine-quarter falloff (gentle near center)
                float n = clamp(d / max(mode_radius, 0.0001), 0.0, 1.0);
                float cosine_q = cos(1.57079632679 * n);
                float edge_fade = 1.0 - smoothstep(0.94, 1.0, n);
                falloff = cosine_q * edge_fade;
            } else {
                falloff = clamp(1.0 - (d / mode_radius), 0.0, 1.0);
            }

            float a = strength * falloff;
            if (a <= 0.0) {
            } else if (brush_mode == 4) {
                // Vacuum brush: advect inward by backtracing to an outward sample
                // This pulls surrounding values toward the center over time
                vec2 from_center = dp;
                float dist = length(from_center);
                if (dist > 0.0001) {
                    vec2 outward_dir = from_center / dist;
                    float pull_px = 2.0 * a;
                    vec2 sample_f = vec2(p) + outward_dir * pull_px;
                    vec3 pulled_rgb = EDGE_PUSH_ENABLED ? sample_rgb_bilinear_clamped(sample_f, size) : sample_rgb_bilinear(sample_f, size);
                    res_rgb = mix(res_rgb, pulled_rgb, a*0.5);
                }
            } else if (brush_mode == 3) {
                // Expelling brush: inverse of vacuum, pushes values away from center
                vec2 from_center = dp;
                float dist = length(from_center);
                if (dist > 0.0001) {
                    vec2 outward_dir = from_center / dist;
                    float n = clamp(dist / max(mode_radius, 0.0001), 0.0, 1.0);
                    float center_boost = cos(1.57079632679 * n);
                    float push_px = (2.2 * center_boost + 0.8) * a;
                    vec2 sample_f = vec2(p) - outward_dir * push_px;
                    vec3 pushed_rgb = EDGE_PUSH_ENABLED ? sample_rgb_bilinear_clamped(sample_f, size) : sample_rgb_bilinear(sample_f, size);
                    res_rgb = mix(res_rgb, pushed_rgb, a);
                }
            } else {
                vec3 target_rgb = vec3(0.0);
                if (brush_mode == 1) {
                    float flash_hue = fract(B.brush_f.z);
                    target_rgb = hsv_to_rgb(vec3(flash_hue, 1.0, 1.0));
                    // Make paint brush colors more vivid and less muddy.
                    float paint_a = clamp(a * 1.9, 0.0, 1.0);
                    res_rgb = mix(res_rgb, target_rgb, paint_a);
                    float luma = dot(res_rgb, vec3(0.2126, 0.7152, 0.0722));
                    vec3 vivid = clamp(vec3(luma) + (res_rgb - vec3(luma)) * 1.45, vec3(0.0), vec3(1.0));
                    res_rgb = mix(res_rgb, vivid, paint_a);
                } else {
                    // Paint/erase mode uses soft brush blend.
                    res_rgb = mix(res_rgb, target_rgb, a);
                }
            }
        }
    }
    if (res_a < 0.5) {
        // Inward edge shadow from the union boundary only (no overlap seam shadow).
        float edge_shadow = newly_dead_this_frame ? 0.0 : dead_union_edge_shadow(p_local);
        float shade = 1.0 - DEAD_EDGE_SHADOW_STRENGTH * edge_shadow;
        vec3 dead_target_rgb = DEAD_VISUAL_RGB * shade;

        // Brief dead-zone fade-in: alpha stores remaining fade time while staying < 0.5.
        if (res_a > 0.0) {
            float fade_t = 1.0 - clamp(res_a / DEAD_FADE_ALPHA_START, 0.0, 1.0);
            float fade_blend = mix(0.30, 0.90, smoothstep(0.0, 1.0, fade_t));
            res_rgb = mix(res_rgb, dead_target_rgb, fade_blend);
            res_a = max(0.0, res_a - DEAD_FADE_ALPHA_STEP);
        } else {
            res_rgb = dead_target_rgb;
        }
        imageStore(dst, p, vec4(res_rgb, res_a));
        return;
    }

    // Build per-ring sums/totals once, then each neighborhood selects a subset
    // via a 12-bit mask where bit i includes ring i+1
    vec3 ring_sum[MAX_RADIUS];
    float ring_tot[MAX_RADIUS];
    for (int ring_i = 0; ring_i < MAX_RADIUS; ring_i++) {
        int base = ring_params.base[ring_i];
        int count = ring_params.count[ring_i];
        vec3 sum_rgb = vec3(0.0);
        for (int oi = 0; oi < count; oi++) {
            ivec2 q = p_local + s_ring_offsets[base + oi];
            sum_rgb += unpack_rgb_alive(s_tile[q.y][q.x]);
        }
        ring_sum[ring_i] = sum_rgb;
        ring_tot[ring_i] = float(max(count, 1));
    }

    float blend_k = clamp(BK.blend.x, 0.0, 1.0);
    float decay_rate = clamp(BK.blend.y, 0.0, 0.010);
    vec3 best_change = vec3(-1.0);
    vec3 best_rgb = res_rgb;

    // Candidate neighborhood count is fixed at 2 in CPU normalization
    for (int c = 0; c < CANDIDATE_COUNT; c++) {
        if (C.enabled[c] == 0) {
            continue;
        }

        vec3 cand_rgb = res_rgb;
        vec3 cand_blend_sum = vec3(0.0);
        vec3 cand_blend_norm = vec3(0.0);
        vec3 sb = vec3(0.0);

        for (int n = 0; n < NEIGHBORHOODS_PER_CANDIDATE; n++) {
            int nh_i = c * NEIGHBORHOODS_PER_CANDIDATE + n;
            uint ring_mask = decode_ring_mask_u12(N.nh[nh_i]);
            if (ring_mask == 0u) {
                continue;
            }

            vec3 sum_rgb = vec3(0.0);
            float tot = 0.0;
            for (int ring_i = 0; ring_i < MAX_RADIUS; ring_i++) {
                if (((ring_mask >> uint(ring_i)) & 1u) == 0u) {
                    continue;
                }
                sum_rgb += ring_sum[ring_i];
                tot += ring_tot[ring_i];
            }
            if (tot <= 0.0) {
                continue;
            }

            vec3 avg_rgb = sum_rgb / tot;

            int rule_base = nh_i * 2;
            for (int r = 0; r < 2; r++) {
                int rule_i = rule_base + r;
                int thr_base = rule_i * 2;
                float wv = decode_weight_u8(WG.w[rule_i]);
                vec3 read_mix = read_triplet_for_rule(rule_i);
                vec3 write_mix = write_triplet_for_rule(rule_i);
                float read_value = dot(avg_rgb, read_mix);

                float lo = decode_unit_u8(T.dvmd[thr_base]);
                float hi = decode_unit_u8(T.dvmd[thr_base + 1]);
                if (read_value >= lo && read_value <= hi) {
                    cand_rgb += write_mix * (wv * 0.075);
                }

                // Keep blend behavior scale compatible with the old 2-rules-per-neighborhood model
                float blend_rule_scale = 0.5;
                cand_blend_sum += write_mix * (read_value * blend_rule_scale);
                cand_blend_norm += write_mix * blend_rule_scale;
                sb += write_mix * abs(wv);
            }
        }

        vec3 sb_scaled = sb * 0.01875;
        vec3 numer = cand_rgb + cand_blend_sum * sb_scaled * blend_k;
        vec3 denom = vec3(1.0) + sb_scaled * blend_k * cand_blend_norm;
        cand_rgb = numer / denom;

        // Per-channel winner selection: each channel keeps the candidate with
        // the largest absolute change for that specific channel
        vec3 d = abs(cand_rgb - res_rgb);
        if (d.r > best_change.r) {
            best_change.r = d.r;
            best_rgb.r = cand_rgb.r;
        }
        if (d.g > best_change.g) {
            best_change.g = d.g;
            best_rgb.g = cand_rgb.g;
        }
        if (d.b > best_change.b) {
            best_change.b = d.b;
            best_rgb.b = cand_rgb.b;
        }
    }
    if (best_change.r >= 0.0 || best_change.g >= 0.0 || best_change.b >= 0.0) {
        res_rgb = best_rgb;
    }

    if (EDGE_PUSH_ENABLED) {
        // Optional inward edge push (kept for future runtime toggle wiring).
        const float EDGE_PUSH_WIDTH = 22.0;
        const float EDGE_PUSH_RECIP_K = 9.0;
        vec2 edge_dir_accum = vec2(0.0);
        float edge_force = 0.0;

        float dl = float(p.x);
        if (dl < EDGE_PUSH_WIDTH) {
            float n = dl / EDGE_PUSH_WIDTH;
            float f = (1.0 / (1.0 + EDGE_PUSH_RECIP_K * n)) * (1.0 - smoothstep(0.72, 1.0, n));
            edge_dir_accum += vec2(1.0, 0.0) * f;
            edge_force += f;
        }
        float dr = float((size.x - 1) - p.x);
        if (dr < EDGE_PUSH_WIDTH) {
            float n = dr / EDGE_PUSH_WIDTH;
            float f = (1.0 / (1.0 + EDGE_PUSH_RECIP_K * n)) * (1.0 - smoothstep(0.72, 1.0, n));
            edge_dir_accum += vec2(-1.0, 0.0) * f;
            edge_force += f;
        }
        float dt = float(p.y);
        if (dt < EDGE_PUSH_WIDTH) {
            float n = dt / EDGE_PUSH_WIDTH;
            float f = (1.0 / (1.0 + EDGE_PUSH_RECIP_K * n)) * (1.0 - smoothstep(0.72, 1.0, n));
            edge_dir_accum += vec2(0.0, 1.0) * f;
            edge_force += f;
        }
        float db = float((size.y - 1) - p.y);
        if (db < EDGE_PUSH_WIDTH) {
            float n = db / EDGE_PUSH_WIDTH;
            float f = (1.0 / (1.0 + EDGE_PUSH_RECIP_K * n)) * (1.0 - smoothstep(0.72, 1.0, n));
            edge_dir_accum += vec2(0.0, -1.0) * f;
            edge_force += f;
        }
        if (edge_force > 0.0) {
            vec2 push_dir = normalize(edge_dir_accum);
            float a = clamp(edge_force * 0.95, 0.0, 1.0);
            float push_px = (2.2 + 1.2 * a) * a;
            vec3 pushed_rgb = EDGE_PUSH_ENABLED
                ? sample_rgb_bilinear_clamped(vec2(p) - push_dir * push_px, size)
                : sample_rgb_bilinear(vec2(p) - push_dir * push_px, size);
            res_rgb = mix(res_rgb, pushed_rgb, a);
            float edge_mult = mix(1.0, 0.9, a); // strongest at edge, fades to 1 inward
            res_rgb *= edge_mult;
        }
    }

    res_rgb -= vec3(decay_rate);
    res_rgb = clamp(res_rgb, vec3(0.0), vec3(1.0));
    imageStore(dst, p, vec4(res_rgb, res_a));
}
