#[compute]
#version 450

// workgroup layout
layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

// image buffers
layout(rg16f, set = 0, binding = 0) uniform readonly image2D velocity_image;
layout(rgba16f, set = 0, binding = 1) uniform image2D color_image;

// other uniforms
layout(push_constant, std430) uniform Params {
    ivec2 size;
    float gain;
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

    // apply gain, clamp, and set in range between -0.5 and 0.5
    vec2 v = clamp(velocity * params.gain, vec2(-1.0), vec2(1.0)) * 0.5;

    // create a color from the motion vector 
    vec4 color = vec4(0.5 + v.x, 0.5 + v.y, 0.5, 1.0);

    // store color in the image
    imageStore(color_image, pixel, color);
}

