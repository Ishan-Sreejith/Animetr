#version 330 compatibility

uniform sampler2D gtexture;
uniform float alphaTestRef = 0.1;

in vec2 texcoord;
in vec4 glcolor;

void main() {
    float alpha = texture(gtexture, texcoord).a * glcolor.a;
    if (alpha < alphaTestRef) {
        discard;
    }
    // Just output something, only depth matters for shadow mapping.
    gl_FragData[0] = vec4(1.0);
}
