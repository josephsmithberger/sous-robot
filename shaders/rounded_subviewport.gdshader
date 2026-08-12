shader_type canvas_item;

// Rounded corners for the SubViewportContainer, with the radius expressed in pixels.
uniform float corner_radius : hint_range(0.0, 128.0) = 20.0;

void fragment() {
    vec4 viewport_color = texture(TEXTURE, UV);

    // Work in pixel space so the corners stay circular at any aspect ratio.
    vec2 size = 1.0 / TEXTURE_PIXEL_SIZE;
    vec2 pixel_position = UV * size;
    vec2 half_size = size * 0.5;
    vec2 distance_from_center = abs(pixel_position - half_size);
    vec2 box = half_size - vec2(corner_radius);
    float distance_to_corner = length(max(distance_from_center - box, vec2(0.0))) - corner_radius;

    float antialias_width = max(fwidth(distance_to_corner), 0.001);
    float mask = 1.0 - smoothstep(0.0, antialias_width, distance_to_corner);

    COLOR = viewport_color;
    COLOR.a *= mask;
}
