#vertex
out vec2 TexCoord;
void main()
{
    TexCoord = texCoord;
    gl_Position = projection * view * vec4(position, 1.0);
} 

#fragment
in vec2 TexCoord;

void main()
{
    FragColor = texture(diffuse, TexCoord);
}
