void main() {
    gl_Position = vec4(aPos + vec3(pos, 0.0), 1.0);
    TexCoord = aTexCoord;
}
