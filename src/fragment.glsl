#version 320 es
precision mediump float;
out vec4 FragColor;

uniform vec4 color;

void main() {
    FragColor = color; //vec4(1.0f, 0.5f, 0.2f, 1.0f);
} 