#version 330 compatibility

uniform mat4 shadowModelView;
uniform mat4 shadowProjection;
uniform mat4 gbufferModelViewInverse;

out vec2 lmcoord;
out vec2 texcoord;
out vec4 glcolor;
out vec3 vNormal;
out vec4 shadowPos;

void main() {
    gl_Position = ftransform();
    texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    lmcoord = (gl_TextureMatrix[1] * gl_MultiTexCoord1).xy;
    glcolor = gl_Color;
    vNormal = normalize(gl_NormalMatrix * gl_Normal);
    
    // --- MANUAL ROBUST SHADOW PROJECTION ---
    vec4 viewPos = gl_ModelViewMatrix * gl_Vertex;
    vec4 playerSpacePos = gbufferModelViewInverse * viewPos;
    shadowPos = shadowProjection * (shadowModelView * playerSpacePos);
}