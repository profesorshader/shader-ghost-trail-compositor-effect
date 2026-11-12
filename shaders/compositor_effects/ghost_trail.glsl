#[compute]
#version 450

// WARNING: This effect is frame-rate dependent.

// workgroup layout
layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

// image buffers
layout(rgba16f, set = 0, binding = 0) uniform image2D color_image;
layout(rg16f, set = 0, binding = 1) uniform image2D prev_frame;
layout(rg16f, set = 0, binding = 2) uniform readonly image2D velocity_image;

// other uniforms
layout(push_constant, std430) uniform Params {
    ivec2 size;
    float gain;
    float strength;
    vec3 glow_color;
    float _pad;
} params;

void main() {
    // skip invocations outside the image bounds
    ivec2 pixel = ivec2(gl_GlobalInvocationID.xy);
    if (pixel.x >= params.size.x || pixel.y >= params.size.y) {
        return;
    }

    // get motion vector for this pixel (x = horizontal, y = vertical)
    vec2 velocity = imageLoad(velocity_image, pixel).xy;

    // get also the accumulated motion vector for this pixel
    vec2 previous = imageLoad(prev_frame, pixel).xy;

    // blend previous and current motion vector
    vec2 blended = mix(velocity, previous, params.strength);

    // apply gain 
    vec2 v = blended * params.gain;

    // compute length and clamp
    float vlen = clamp(length(v), 0.0, 1.0);

    // compute final glow color
    vec3 glow = params.glow_color * vlen;

    // load sceen color
    vec4 screen = imageLoad(color_image, pixel);

    // add glow color to the screen color
    vec3 final = clamp(screen.rgb + glow.rgb, vec3(0.0), vec3(1.0));

    // save to screen
    imageStore(color_image, pixel, vec4(final, 1.0));

    // store current blended frame as next frame's "previous"
    imageStore(prev_frame, pixel, vec4(blended.r, blended.g, 0.0, 1.0));    
}

