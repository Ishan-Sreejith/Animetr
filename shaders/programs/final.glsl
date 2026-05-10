// GBuffer - Final
// Written by Kevin Edzenga, ProcStack; 2022-2024
//

/* -- -- -- -- -- --
  -Shadow Pass is not being used.
    Buffer currently has Sun Shadow written to it
    Should be block luminance;
      Transparent blocks included
   -- -- -- -- -- -- 
  Notes :
    Highlighted Block edge thickness is set in gbuffer_basic.glsl
   
*/


#ifdef VSH

uniform sampler2D gnormal;
uniform float aspectRatio;
uniform float viewWidth;
uniform float viewHeight;
uniform float sunAngle;

uniform vec3 sunPosition;

varying vec2 texcoord;
varying vec2 res;

varying vec3 sunWorldPos;
varying float dayNight;

void main() {
  
  gl_Position = ftransform();
  texcoord = (gl_MultiTexCoord0).xy;
  
  res = vec2( 1.0/viewWidth, 1.0/viewHeight);
	
  dayNight = step(.5,fract(sunAngle*2.0));
}
#endif

#ifdef FSH

/* --
const int gcolorFormat = RGBA8;
const int gdepthFormat = RGBA16;
const int gnormalFormat = RGB10_A2;
const float eyeBrightnessHalflife = 4.0f;
 -- */
 
#include "/shaders.settings"
#include "utils/mathFuncs.glsl"

float hash12(vec2 p) {
  vec3 p3 = fract(vec3(p.xyx) * 0.1031);
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

uniform sampler2D colortex0; // Diffuse Pass
uniform sampler2D colortex1; // Depth Pass
uniform sampler2D colortex2; // Normal Pass

uniform sampler2D shadowcolor0;
uniform sampler2D shadowcolor1;

uniform sampler2D gaux1; // Bind 7;
uniform sampler2D gaux2; // Bind 8; 40% Res Glow Pass
uniform sampler2D gaux3; // Bind 9; 30% Res Glow Pass
uniform sampler2D gaux4; // Bind 10; 30% Res Glow Pass
uniform sampler2D colortex9; // Bind 17; Known working from terrain gbuffer

uniform sampler2D gcolor;
uniform sampler2D gdepth;
uniform sampler2D gnormal;
uniform sampler2D composite;
uniform vec3 sunVec;
uniform vec3 sunPosition;
uniform mat4 shadowProjection;
uniform int isEyeInWater;
uniform vec2 texelSize;
uniform float aspectRatio;
uniform float viewWidth;
uniform float viewHeight;
uniform float near;
uniform float far;
uniform vec3 fogColor;
uniform vec3 skyColor; 
uniform float rainStrength;
uniform int worldTime;
uniform float nightVision;

uniform int biome;
uniform float BiomeTemp;

uniform float darknessFactor; //                   strength of the darkness effect (0.0-1.0)
uniform float darknessLightFactor; //              lightmap variations caused by the darkness effect (0.0-1.0) 

const float eyeBrightnessHalflife = 4.0f;
uniform ivec2 eyeBrightnessSmooth;

uniform float InTheEnd;

varying vec2 texcoord;

varying vec2 res;
varying float dayNight;

  
// -- -- -- -- -- -- -- --
// -- Box Blur Sampler  -- --
// -- -- -- -- -- -- -- -- -- --
vec4 boxSample( sampler2D tex, vec2 uv, vec2 reachMult, float blend ){

  vec2 curUVOffset;
  vec4 curCd;
  
  vec4 blendCd = texture2D(tex, uv);
  
  curUVOffset = reachMult * vec2( -1.0, -1.0 );
  curCd = texture2D(tex, uv+curUVOffset);
  blendCd = mix( blendCd, curCd, blend);
  curUVOffset = reachMult * vec2( -1.0, 0.0 );
  curCd = texture2D(tex, uv+curUVOffset);
  blendCd = mix( blendCd, curCd, blend);
  curUVOffset = reachMult * vec2( -1.0, 1.0 );
  curCd = texture2D(tex, uv+curUVOffset);
  blendCd = mix( blendCd, curCd, blend);
  
  curUVOffset = reachMult * vec2( 0.0, -1.0 );
  curCd = texture2D(tex, uv+curUVOffset);
  blendCd = mix( blendCd, curCd, blend);
  curUVOffset = reachMult * vec2( 0.0, 1.0 );
  curCd = texture2D(tex, uv+curUVOffset);
  blendCd = mix( blendCd, curCd, blend);
  
  curUVOffset = reachMult * vec2( 1.0, -1.0 );
  curCd = texture2D(tex, uv+curUVOffset);
  blendCd = mix( blendCd, curCd, blend);
  curUVOffset = reachMult * vec2( 1.0, 0.0 );
  curCd = texture2D(tex, uv+curUVOffset);
  blendCd = mix( blendCd, curCd, blend);
  curUVOffset = reachMult * vec2( 1.0, 1.0 );
  curCd = texture2D(tex, uv+curUVOffset);
  blendCd = mix( blendCd, curCd, blend);
  
  return blendCd;
}


// -- -- -- -- -- -- -- -- -- -- -- -- --
// -- Depth & Normal LookUp & Blending -- --
// -- -- -- -- -- -- -- -- -- -- -- -- -- -- --
void edgeLookUp(  sampler2D txColor, sampler2D txDepth, sampler2D txNormal,
                  vec2 uv, vec2 uvOffset,
                  float depthRef, vec3 normalRef, float thresh,
                  inout vec3 avgNormal, inout float innerEdge, inout float outerEdge ){

  vec2 uvDepthLimit = uv+uvOffset;
  vec2 uvNormalLimit = uv+uvOffset*1.5;
  float curDepth = texture2D(txDepth, uvDepthLimit).r;
  vec3 curNormal = texture2D(txNormal, uvNormalLimit).rgb*2.0-1.0;
  
  float curNormalDot = 1.0-abs(dot(normalRef, curNormal));
  curNormalDot *= curNormalDot;
  //curDepth = max(0.0, abs(curDepth - depthRef)-.009)*50.5;
  curDepth = clamp( (abs(curDepth - depthRef)-.0075)*8.0,0.0,1.0);

  float curInf = step( curDepth, thresh );

  innerEdge = mix( innerEdge, curNormalDot, .125*curInf );
  outerEdge = max( outerEdge, curDepth );
  avgNormal = (mix( avgNormal, curNormal, .125*curInf ));
  
}


// -- -- -- -- -- -- -- -- -- -- -- -- --
// -- Sample Depth & Normals; 3x3 - -- -- --
// -- -- -- -- -- -- -- -- -- -- -- -- -- -- --
// TODO : Implement Base Quality by using Cross instead of 3x3
void findEdges( sampler2D txColor, sampler2D txDepth, sampler2D txNormal,
                vec2 uv, vec2 txRes,
                float depthRef, vec3 normalRef, float thresh,
                inout vec3 avgNormal, inout float innerEdgePerc, inout float outerEdgePerc ){
  
  float innerEdge = 0.0;
  float outerEdge = 0.0;
  
  vec2 uvOffsetReach = txRes;
  
  vec2 curUVOffset;
  curUVOffset = uvOffsetReach * vec2( -1.0, -1.0 );
  edgeLookUp( txColor,txDepth,txNormal, uv,curUVOffset,depthRef,normalRef,thresh,avgNormal, innerEdge,outerEdge );
  curUVOffset = uvOffsetReach * vec2( -1.0, 0.0 );
  edgeLookUp( txColor,txDepth,txNormal, uv,curUVOffset,depthRef,normalRef,thresh,avgNormal, innerEdge,outerEdge );
  curUVOffset = uvOffsetReach * vec2( -1.0, 1.0 );
  edgeLookUp( txColor,txDepth,txNormal, uv,curUVOffset,depthRef,normalRef,thresh,avgNormal, innerEdge,outerEdge );
  
  curUVOffset = uvOffsetReach * vec2( 0.0, -1.0 );
  edgeLookUp( txColor,txDepth,txNormal, uv,curUVOffset,depthRef,normalRef,thresh,avgNormal, innerEdge,outerEdge );
  curUVOffset = uvOffsetReach * vec2( 0.0, 1.0 );
  edgeLookUp( txColor,txDepth,txNormal, uv,curUVOffset,depthRef,normalRef,thresh,avgNormal, innerEdge,outerEdge );
  
  curUVOffset = uvOffsetReach * vec2( 1.0, -1.0 );
  edgeLookUp( txColor,txDepth,txNormal, uv,curUVOffset,depthRef,normalRef,thresh,avgNormal, innerEdge,outerEdge );
  curUVOffset = uvOffsetReach * vec2( 1.0, 0.0 );
  edgeLookUp( txColor,txDepth,txNormal, uv,curUVOffset,depthRef,normalRef,thresh,avgNormal, innerEdge,outerEdge );
  curUVOffset = uvOffsetReach * vec2( 1.0, 1.0 );
  edgeLookUp( txColor,txDepth,txNormal, uv,curUVOffset,depthRef,normalRef,thresh,avgNormal, innerEdge,outerEdge );
  
  outerEdge *= step(0.05, outerEdge); 
  
  avgNormal = normalize(avgNormal);
  innerEdgePerc = innerEdge;
  outerEdgePerc = outerEdge;
}



// == == == == == == == == == == == == ==
// == MAIN VOID = == == == == == == == == ==
// == == == == == == == == == == == == == == ==

void main() {

// -- -- -- -- -- -- -- -- -- -- --
// -- Color, Depth, Normal,   -- -- --
// --   Shadow, & Glow Reads  -- -- -- --
// -- -- -- -- -- -- -- -- -- -- -- -- -- --
  vec2 uv = texcoord;
  vec2 uvShifted = abs(uv-.5);
  uvShifted *= uvShifted;
  
  vec4 baseCd = texture2D(colortex0, uv);
  vec4 outCd = baseCd;
  vec2 depthEffGlowBase = texture2D(colortex1, uv).rg;
  float depthBase = depthEffGlowBase.r;
  float effGlowBase = depthEffGlowBase.g;
  
  vec4 normalCd = texture2D(colortex2, uv);
  vec3 dataCd = texture2D(gaux1, uv).xyz;
  vec4 spectralDataCd = texture2D(colortex9, uv);
  
  // Entity mask stored in gaux1.b (set in gbuffers_entities.glsl)
  float entityMask = step(0.5, dataCd.b);
  // Foliage heuristic: green-dominant pixels (trees/plants)
  float foliageMask = step(baseCd.r * 1.15, baseCd.g) * step(baseCd.b * 1.05, baseCd.g);


// -- -- -- -- -- -- -- --
// -- Glow Passes -- -- -- --
// -- -- -- -- -- -- -- -- -- --
  vec3 blurInitCd = texture2D(gaux2, uv*.4).rgb; // Bind 8
  vec3 blurFirstCd = texture2D(gaux3, uv*.3).rgb; // Bind 9
  vec3 blurSecondCd = texture2D(gaux4, uv*.3).rgb; // Bind 9
  
  
// -- -- -- -- -- -- -- --
// -- Depth Tweaks - -- -- --
// -- -- -- -- -- -- -- -- -- --
  float depth = 1.0-depthBase;//biasToOne(depthBase);
  //depth = min(1.0, depth*depth*min(1.0,1.5-depth));
  float depthCos = cos(depth*PI*.5);//*-.5+.5;
  
  
// -- -- -- -- -- 
// -- Shadows  -- --
// -- -- -- -- -- -- --
  //float shadow = dataCd.x;
  //float shadowDepth = dataCd.y;
  //shadowDepth = 1.0-(1.0-shadowDepth)*(1.0-shadowDepth);
  //shadowDepth *= shadowDepth;


// -- -- -- -- -- -- -- --
// -- Depth Blur -- -- -- --
// -- -- -- -- -- -- -- -- -- --
  // All threads are in or out, leaving for now
  if( UnderWaterBlur && isEyeInWater >= 1 ){
    float depthBlurInf = smoothstep( .5, 1.5, depth);//biasToOne(depthBase);
    
    float depthBlurTime = worldTime*.07 + depth*3.0;
    float depthBlurWarpMag = .006;
    float uvMult = 20.0 + 10.0*depthCos;
    
    vec2 depthBlurUV = uv + vec2( sin(uv.x*uvMult+depthBlurTime), cos(uv.y*uvMult+depthBlurTime) )*depthBlurWarpMag*depthBlurInf;
    vec2 depthBlurReach = vec2( max(0.0,depthBlurInf-length(blurInitCd.rgb)) * texelSize * 6.0 * (1.0-nightVision));
    vec4 depthBlurCd = boxSample( colortex0, depthBlurUV, depthBlurReach, .25 );
    depthBlurCd.rgb = mix( fogColor*depthCos, (fogColor*.5+.5)*depthBlurCd.rgb, min(1.0,(1.0-depth*.5)));
    
    float eyeWaterInf = (1.0-isEyeInWater*.2);
    //float fogBlendDepth = ((depth+.5)*depth+.8);
    //depthBlurCd.rgb = min(vec3(1.0), depthBlurCd.rgb*mix( (fogColor*fogBlendDepth), vec3(1.0), fogBlendDepth*eyeWaterInf));

    
    baseCd = depthBlurCd;
    outCd = depthBlurCd;
    
  }
  
  
// -- -- -- -- --
// -- To Cam - -- --
// -- -- -- -- -- -- --
  // Fit Normal
  normalCd.rgb = normalCd.rgb*2.0-1.0;
  vec3 nCenter = normalize(normalCd.rgb);
  
  // Dot To Camera
  float dotToCam = dot(normalCd.rgb,normalize(vec3(.5-uv,1.0)));
  float dotToCamClamp = max(0.0, dotToCam);
  dotToCamClamp = smoothstep(.2,1.0, dotToCamClamp);


// -- -- -- -- -- -- -- 
// -- Sky Influence  -- --
// -- -- -- -- -- -- -- -- --
  float skyBrightnessMult=eyeBrightnessSmooth.y*0.004166666666666666;//  1.0/240.0
  float skyBrightnessInf = skyBrightnessMult*.5+.5;
  

// -- -- -- -- -- -- -- 
// -- Rain Influence  -- --
// -- -- -- -- -- -- -- -- --
  float rainInf = (1.0-rainStrength*.7);
  rainInf = mix( 1.0, rainInf, skyBrightnessMult);
  
// -- -- -- -- -- -- -- --
// -- Sticker Edges  -- --
// -- -- -- -- -- -- -- --
  float stickerEdge = 0.0;
  float edgeAirMax = 0.0;
  float edgeAnyMax = 0.0;
  float borderScale = mix(1.0, 2.0, smoothstep(0.3, 0.9, depthBase));
#if FastMode
  borderScale = 1.0;
#endif
  if (depthBase < 0.9999) {
    for (int x = -1; x <= 1; x++) {
      for (int y = -1; y <= 1; y++) {
        if (x == 0 && y == 0) continue;
        vec2 o = vec2(x, y) * texelSize * BorderThickness * borderScale;
        float nd = texture2D(colortex1, uv + o).r;
        vec3 nn = texture2D(colortex2, uv + o).rgb * 2.0 - 1.0;
        
        float depthDiff = abs(nd - depthBase);
        // Robust air/sky/void detection
        float isSkyNeighbor = step(0.9999, nd);
        float isSkyCurrent = step(0.9999, depthBase);
        
        // Edge triggering: 
        // 1. Silhouette against sky
        float silhouette = step(0.5, isSkyNeighbor) * (1.0 - step(0.5, isSkyCurrent));
        // 2. Large depth gap between objects (stickier feel)
        float worldEdge = step(DepthThreshold * 4.0, depthDiff) * (1.0 - step(0.5, isSkyNeighbor));
        
        edgeAirMax = max(edgeAirMax, max(silhouette, worldEdge));
      }
    }
  }
  // Only outline where geometry meets air/background or far objects
  stickerEdge = clamp(edgeAirMax, 0.0, 1.0);
  
  // Fade top-face edges when camera is above (prevents white tops at eye level)
  float topFace = step(0.85, nCenter.y) * step(0.7, dotToCamClamp);
  stickerEdge *= mix(1.0, 1.0 - TopEdgeFade, topFace);
  
  // Thicker border for entities
  float stickerEdgeEntity = 0.0;
  if (entityMask > 0.5) {
    float thick = BorderThickness + 1.0;
    for (int x = -1; x <= 1; x++) {
      for (int y = -1; y <= 1; y++) {
        if (x == 0 && y == 0) continue;
        vec2 o = vec2(x, y) * texelSize * thick;
        float nd = texture2D(colortex1, uv + o).r;
        vec3 nn = texture2D(colortex2, uv + o).rgb * 2.0 - 1.0;
        float depthDiff = nd - depthBase;
        float edgeAir = step(DepthThreshold * 0.5, abs(depthDiff));
        float edgeNormal = step(NormalThreshold * 0.6, length(nCenter - normalize(nn)));
        stickerEdgeEntity = max(stickerEdgeEntity, max(edgeAir, edgeNormal));
      }
    }
  }
  stickerEdgeEntity = clamp(stickerEdgeEntity, 0.0, 1.0);
  stickerEdgeEntity *= mix(1.0, 1.0 - TopEdgeFade, topFace);

  
// -- -- -- -- -- -- -- --
// -- Edge Detection -- -- --
// -- -- -- -- -- -- -- -- -- --
  float edgeDistanceThresh = .003;
  // Edge detect width shift, based on rain or being in water/lava/snow
  float reachOffset = min(.4,isEyeInWater*.5) + rainStrength*1.5;
  // Edge detect width
  float reachMult = mix(2.75-dataCd.r*1.55, .6-skyBrightnessMult*.15+reachOffset, depth );//1.0;//depthBase*.5+.5 ;

  // Final Edge Value Multipliers
  float innerMult = 1.0;
  float outerMult = 1.0;

#ifdef NETHER
  // Tweak Nether settings 
  skyBrightnessInf = 1.0;
  // Make the edge lines fatter in the dark
	float invLighting = 1.0-(dataCd.r*.4+.35);
  reachMult *= 1.1+invLighting;
  // Bias the Cosine Depth closer to the camera
  //depthCos=biasToOne(depthCos);
  depthCos=biasToOne(depthCos*(2.2*invLighting));
  
  innerMult = .95;
  outerMult = 1.35;
#endif
  
  vec3 avgNormal = normalCd.rgb;
  float innerEdgePerc = 0.0;
  float outerEdgePerc = 0.0;
  findEdges( colortex0, colortex1, colortex2,
             uv, res*(1.5)*reachMult*EdgeShading,
             depthBase, normalCd.rgb, edgeDistanceThresh, avgNormal,
             innerEdgePerc,outerEdgePerc );

  innerEdgePerc *= 1.0-min(1.0,float(max(0,isEyeInWater))*.35);
  innerEdgePerc *= dotToCamClamp*2.5-reachOffset*1.5;
  
  // Screen edges influence
  float screenEdgeMult = max(0.0, 1.0-maxComponent(uvShifted) * 2.5); // Higher the #, darker the edges
  // Edge depth boost
  float edgeDepthInf = (depthCos*.8+.02)*(1.85-dataCd.r*.5);
  
  float outerEdgeInf =  1.0 - max( 0.0, (edgeDepthInf-.825)*4.0 ); 

  // Output Individual Edge Values
  innerEdgePerc = clamp(innerEdgePerc * edgeDepthInf * screenEdgeMult * innerMult, 0.0, rainInf )  ;
  outerEdgePerc = clamp( outerEdgePerc * edgeDepthInf * outerMult, 0.0, rainInf * outerEdgeInf ) ;
	
  
  // Combine Inner & Outer Edge Values
  //float edgeInsideOutsidePerc = clamp(max(innerEdgePerc,outerEdgePerc)*(depthCos-.01)*10.5, 0.0, rainInf-float(isEyeInWater)*.27 );
  float edgeInsideOutsidePerc = clamp(max(innerEdgePerc,outerEdgePerc), 0.0, rainInf-float(isEyeInWater)*.27 );
  #if EnableBorders
    // Dark ink outlines (optional)
  #else
    edgeInsideOutsidePerc = 0.0;
  #endif

  


// -- -- -- -- -- -- -- -- -- -- -- -- --
// -- World Specific Edge Colorization -- --
// -- -- -- -- -- -- -- -- -- -- -- -- -- -- --
#ifdef OVERWORLD
  // Edge boost around well lit areas
  float sunEdgeInf = dot( sunVec, avgNormal );
  outCd.rgb += mix( outCd.rgb, fogColor, dataCd.r*skyBrightnessMult)*edgeInsideOutsidePerc*dataCd.r*.2*depthCos;
#elif defined NETHER
  //outCd.rgb *= outCd.rgb * vec3(.8,.6,.2) * edgeInsideOutsidePerc;// * (shadow*.3+.7);
	vec3 netherEdgeCd = mix( outCd.rgb*vec3(.75,.5,.2), mix(fogColor,outCd.rgb,depth), dataCd.r*.85);
	
  outCd.rgb =  mix(outCd.rgb, netherEdgeCd, edgeInsideOutsidePerc);
#endif
  
  

// -- -- -- -- -- -- -- --
// -- Glow Mixing -- -- -- --
// -- -- -- -- -- -- -- -- -- --

  float lavaSnowFogInf = 1.0 - min(1.0, max(0.0,isEyeInWater-1.0)) ;
  
  vec3 outGlowCd = max( blurSecondCd, max(blurInitCd, blurFirstCd) );
  #if EnableGlow
    outCd.rgb += outGlowCd * GlowBrightness;
  #endif
  
  
  float edgeCdInf = step(depthBase, .9999);
  edgeCdInf *= lavaSnowFogInf;
  
  // Apply Edge Coloring
  outCd.rgb += outCd.rgb*.3*edgeInsideOutsidePerc*edgeCdInf;

  // Halo for entities/foliage (thicker border)
  float haloEdge = 0.0;
#if !FastMode
  if (HaloThickness > 0.01 && (entityMask > 0.5 || foliageMask > 0.5)) {
    float thick = BorderThickness + HaloThickness;
    for (int x = -1; x <= 1; x++) {
      for (int y = -1; y <= 1; y++) {
        if (x == 0 && y == 0) continue;
        vec2 o = vec2(x, y) * texelSize * thick;
        float nd = texture2D(colortex1, uv + o).r;
        vec3 nn = texture2D(colortex2, uv + o).rgb * 2.0 - 1.0;
        float depthDiff = nd - depthBase;
        float edgeAir = step(DepthThreshold * 0.5, abs(depthDiff));
        float edgeNormal = step(NormalThreshold * 0.6, length(nCenter - normalize(nn)));
        haloEdge = max(haloEdge, max(edgeAir, edgeNormal));
      }
    }
  }
  haloEdge = clamp(haloEdge, 0.0, 1.0);
#endif

  // White edge mask (apply later after grading/quant)
  // Borders always on by default
  float whiteEdge = 0.0;
  // Animals/mobs: always use thicker halo
  whiteEdge = max(whiteEdge, haloEdge * entityMask * WhiteEdgeEntities);
  // Blocks/objects: only where touching air (sky/background)
  whiteEdge = max(whiteEdge, stickerEdge * (1.0 - entityMask));
  
  // Boost Glowing Entity's Color (disabled when glow is off)
  #if EnableGlow
    float spectralInt = spectralDataCd.b;// + (spectralDataCd.g-.5)*3.0;
    outCd.rgb += outCd.rgb * spectralInt * spectralDataCd.r;
  #endif
  

// -- -- -- -- -- -- -- --
// -- World Color Modes -- -- --
// -- -- -- -- -- -- -- -- -- --

    if( WorldColor ){ // Greyscale
      outCd.rgb = vec3( luma(baseCd.rgb) );
    }

  // Preserve base hue to avoid weird grass tinting
  vec3 baseHSV = rgb2hsv(baseCd.rgb);
  vec3 outHSV = rgb2hsv(outCd.rgb);
  outHSV.x = mix(outHSV.x, baseHSV.x, HuePreserve);
  outHSV.y = mix(outHSV.y, baseHSV.y, HuePreserve * 0.6);
  // Color pop without brightening
  outHSV.y = clamp(outHSV.y * ColorPop, 0.0, 1.0);
  outHSV.z *= (1.0 - (ColorPop - 1.0) * ValueComp);
  outCd.rgb = hsv2rgb(outHSV);

  // Dirt palette correction (muted pastel brown)
  float h = baseHSV.x;
  float s = baseHSV.y;
  float v = baseHSV.z;
  float dirtHue = smoothstep(0.05, 0.07, h) * (1.0 - smoothstep(0.12, 0.14, h));
  float dirtSat = smoothstep(0.25, 0.4, s);
  float dirtVal = 1.0 - smoothstep(0.6, 0.75, v);
  float dirtMask = dirtHue * dirtSat * dirtVal;
  vec3 dirtBase = vec3(0.604, 0.435, 0.310);  // #9A6F4F
  vec3 dirtShadow = vec3(0.478, 0.341, 0.235); // #7A573C
  float dirtT = clamp((luma(outCd.rgb) - 0.25) / 0.35, 0.0, 1.0);
  vec3 dirtTarget = mix(dirtShadow, dirtBase, dirtT);
  outCd.rgb = mix(outCd.rgb, dirtTarget, clamp(dirtMask * 0.8, 0.0, 1.0));

  // Sand palette correction (soft pastel)
  float sandHue = smoothstep(0.08, 0.10, h) * (1.0 - smoothstep(0.17, 0.19, h));
  float sandSat = smoothstep(0.15, 0.25, s) * (1.0 - smoothstep(0.55, 0.65, s));
  float sandVal = smoothstep(0.55, 0.7, v);
  float sandMask = sandHue * sandSat * sandVal;
  vec3 sandBase = vec3(0.78, 0.71, 0.56);  // slightly darker than #D8C89E
  vec3 sandShadow = vec3(0.66, 0.58, 0.42);
  float sandT = clamp((luma(outCd.rgb) - 0.2) / 0.5, 0.0, 1.0);
  vec3 sandTarget = mix(sandShadow, sandBase, sandT);
  outCd.rgb = mix(outCd.rgb, sandTarget, clamp(sandMask * 0.75, 0.0, 1.0));

  // Water palette correction (soft teal-blue)
  float waterHue = smoothstep(0.50, 0.54, h) * (1.0 - smoothstep(0.68, 0.72, h));
  float waterSat = smoothstep(0.2, 0.35, s);
  float waterGeom = step(0.1, length(nCenter)) * (1.0 - step(0.999, depthBase));
  float waterMask = waterHue * waterSat * waterGeom;
  vec3 waterBase = vec3(0.435, 0.686, 0.878); // #6FAFE0
  vec3 waterDeep = vec3(0.302, 0.561, 0.761); // #4D8FC2
  float waterT = clamp((v - 0.25) / 0.6, 0.0, 1.0);
  vec3 waterTarget = mix(waterDeep, waterBase, waterT);
  outCd.rgb = mix(outCd.rgb, waterTarget, clamp(waterMask * 0.85, 0.0, 1.0));
  #if !FastMode
    float wNoise = hash12(uv * vec2(viewWidth, viewHeight));
    outCd.rgb += waterMask * WaterSparkle * (0.5 + 0.5 * wNoise) * (1.0 - dotToCamClamp);
  #endif

  // Pastel NPR palette (muted + soft boost)
  float lumaPastel = dot(outCd.rgb, vec3(0.299, 0.587, 0.114));
  outCd.rgb = mix(vec3(lumaPastel), outCd.rgb, PastelSaturation);
  outCd.rgb = mix(outCd.rgb, vec3(0.95, 0.95, 0.95), PastelWash);
  outCd.rgb *= vec3(PastelShiftR, PastelShiftG, PastelShiftB);


// -- -- -- -- -- -- -- -- -- --
// -- Debugging Visualization -- --
// -- -- -- -- -- -- -- -- -- -- -- --

// Shadow Helper Mini Window
//   hmmmmm picture-in-picture
//     drooollllssss
//

// Debug - Shadow Cam
#if ( DebugView == 2 )
	//float fitWidth = 1.0 + fract(viewWidth/float(shadowMapResolution))*.5;
	float fitWidth = 1.0 + aspectRatio*.45;
	vec2 debugShadowUV = vec2( 1.0-uv.y, (uv.x-.5)*fitWidth+.5)*2.35;
	
	vec2 debugShadowCdUV = debugShadowUV + vec2(-0.1,-2.15);
	vec2 debugShadowTexUV = 1.0-debugShadowCdUV;
	debugShadowTexUV.x = mix( debugShadowCdUV.x, 1.0-debugShadowCdUV.x, dayNight );
	vec3 shadowCd = texture2D(shadowcolor0, debugShadowTexUV ).rgb;
	debugShadowCdUV = abs(debugShadowCdUV-.5);
	float shadowHelperMix = max(debugShadowCdUV.y,debugShadowCdUV.x);
	shadowCd = mix( vec3(0.0), shadowCd, step(shadowHelperMix, 0.50));

	// -- 
	outCd.rgb = mix( outCd.rgb, shadowCd, step(shadowHelperMix, 0.502));

	// -- -- --

	debugShadowCdUV = debugShadowUV + vec2(-1.2,-2.15);
	debugShadowTexUV = 1.0-debugShadowCdUV;
	debugShadowTexUV.x = mix( debugShadowCdUV.x, 1.0-debugShadowCdUV.x, dayNight );
	vec4 shadowData = texture2D(shadowcolor1, debugShadowTexUV );
	shadowCd = texture2D(shadowcolor0, debugShadowTexUV ).rgb;
	shadowData.g = mix( 1.0, shadowData.g, step(0.0,shadowData.g));
	shadowCd = mix( shadowData.ggg, shadowCd, step(0.5, shadowData.r));
	debugShadowCdUV = abs(debugShadowCdUV-.5);
	shadowHelperMix = max(debugShadowCdUV.y,debugShadowCdUV.x);
	shadowData.rgb = mix( vec3(0.0), shadowCd, step(shadowHelperMix, 0.50));
	// -- 
	outCd.rgb = mix( outCd.rgb, shadowData.rgb, step(shadowHelperMix, 0.502));

	// -- -- --
	
// Debug - Shadow Debug
//   Adding the mini cam cause its fun
#elif ( DebugView == 3 )
	//float fitWidth = 1.0 + fract(viewWidth/float(shadowMapResolution))*.5;
	float fitWidth = 1.0 + aspectRatio*.45;
	vec2 debugShadowUV = vec2( 1.0-uv.y, ((uv.x)-.5)*fitWidth+.5)*2.35 + vec2(-1.2,-2.15);
	//debugShadowUV.x = mix( debugShadowUV.x, 1.0-debugShadowUV.x, step( 0.0, sunVec.z));
	vec3 shadowCd = texture2D(shadowcolor0, debugShadowUV ).xyz;
	debugShadowUV = abs(debugShadowUV-.5);
	float shadowHelperMix = max(debugShadowUV.y,debugShadowUV.x);
	shadowCd = mix( vec3(0.0), shadowCd.rgb, step(shadowHelperMix, 0.50));
	
	//shadowCd=vec3(abs(sunVec.x));
	outCd.rgb = mix( outCd.rgb, shadowCd, step(shadowHelperMix, 0.502));


// Debug - Vanilla -vs- procPromo Debugger
#elif ( DebugView == 4 )
	float debugBlender = step( .5, uv.x);
	outCd = mix( baseCd, outCd, debugBlender);
	
#endif

// Final color grading (softer, less harsh)
vec3 preGrade = outCd.rgb;
  float lumaCd = luma(outCd.rgb);
  outCd.rgb = mix(vec3(lumaCd), outCd.rgb, SaturationBoost);
  outCd.rgb = (outCd.rgb - 0.5) * ContrastBoost + 0.5;
  outCd.rgb = clamp(outCd.rgb, 0.0, 1.0);
  // Softer lighting: lift shadows slightly
  outCd.rgb += LightSoftness * (1.0 - lumaCd) * 0.06;
  outCd.rgb = clamp(outCd.rgb, 0.0, 1.0);
  // Warm tint
  outCd.rgb = mix(outCd.rgb, outCd.rgb * vec3(1.03, 1.01, 0.98), WarmTintMix);


  // Candy Mode palette swap (strong override)
  // Candy block moved late for better visibility

// Toon quantization with soft blend
vec3 quantCd = floor(outCd.rgb * CelLevels) / CelLevels;
outCd.rgb = mix(outCd.rgb, quantCd, SoftLight);
outCd.rgb = mix(outCd.rgb, preGrade, ColorSoftness);

// Slight edge shrink for entities/foliage (makes them look smaller)
float shrinkMask = haloEdge * (step(0.5, entityMask) + step(0.5, foliageMask));
outCd.rgb = mix(outCd.rgb, fogColor.rgb, clamp(shrinkMask * ObjectShrink, 0.0, 1.0));

// Optional extra detail (restore texture detail)
#if EnableExtraDetail
  // Blend in original texture detail using a soft luminosity overlay
  // This preserves the anime look while making surfaces feel less flat
  vec3 detailBase = baseCd.rgb;
  vec3 overlayDetail = mix(outCd.rgb, outCd.rgb * (detailBase * 2.1), 0.35);
  outCd.rgb = mix(outCd.rgb, overlayDetail, ExtraDetailStrength * (1.1 - lumaCd * 0.5));
#endif

// Apply white sticker border last (soft edge)
float softEdge = smoothstep(0.2, 0.8, whiteEdge) * BorderOpacity;
softEdge = mix(softEdge, whiteEdge, 1.0 - BorderSoftness);

// Hand-drawn feel: subtle grain + outline wobble (screen-stable)
float noise = hash12(texcoord * vec2(viewWidth, viewHeight));
outCd.rgb *= mix(1.0, 0.97 + 0.06 * noise, HandDrawn * 0.6);
softEdge *= mix(1.0, 0.85 + 0.3 * noise, HandDrawn);

// Ensure borders remain visible
softEdge = max(softEdge, whiteEdge * 0.6);

  float outlineDarken = smoothstep(0.7, 0.95, lumaCd);
  vec3 outlineCol = mix(vec3(1.0), vec3(0.92), outlineDarken);
  // Fix: Ensure border has proper contrast on dark objects
  // Instead of darkening low-luma objects, use inverse luminance for contrast
  float darkObjFix = smoothstep(0.15, 0.5, lumaCd);
  vec3 borderCol = mix(outCd.rgb * 1.4, outlineCol, darkObjFix);
  // Grass/Foliage should not have the border (User Request)
  softEdge *= (1.0 - foliageMask);
  outCd.rgb = mix(outCd.rgb, borderCol, clamp(softEdge, 0.0, 1.0));

#if CandyMode == 1
  // Targeted Candy Mode: Material-specific and Biome-aware
  float cmLuma = luma(outCd.rgb);
  vec3 hsv = rgb2hsv(outCd.rgb);
  
  // 1. Material Detection
  // Robust Foliage detection (covers greens, yellows, browns)
  float foliageMaskMod = (smoothstep(0.08, 0.5, hsv.y) * 
                        (step(0.1, hsv.x) * step(hsv.x, 0.45))) + foliageMask;
  foliageMaskMod = clamp(foliageMaskMod, 0.0, 1.0);
  
  // Water detection (Blue-Cyan range)
  float waterMaskMod = step(0.48, hsv.x) * step(hsv.x, 0.72) * smoothstep(0.1, 0.6, hsv.y);
  
  // 2. Biome-aware Palettes
  // Heuristic for biome warmth based on skyColor and BiomeTemp (if available)
  float warmth = smoothstep(0.6, 1.1, luma(skyColor) / luma(vec3(0.5, 0.7, 1.0)));
  
  vec3 candyFoliage;
  vec3 candyWater;
  vec3 blockTint;
  
  if (warmth > 0.85) { // Warm/Arid (Desert, Savanna)
     candyFoliage = vec3(1.0, 0.82, 0.55); // Peach/Gold
     candyWater = vec3(0.5, 0.95, 0.8); // Mint/Seafoam
     blockTint = vec3(1.05, 1.02, 0.95); // Sand glow
  } else if (warmth < 0.42 || BiomeTemp < 0.3) { // Cold/Snowy
     candyFoliage = vec3(0.65, 0.95, 1.0); // Cyan/Crystal
     candyWater = vec3(0.85, 0.7, 1.0); // Lavender/Ice
     blockTint = vec3(0.95, 0.98, 1.05); // Cool lift
  } else { // Temperate (Forest, Plains)
     candyFoliage = vec3(1.0, 0.68, 0.88); // Cotton Candy Pink
     candyWater = vec3(0.6, 0.95, 1.0); // Bright Cyan
     blockTint = vec3(1.04, 0.98, 1.05); // Soft Magenta lift
  }
  
  // 3. Apply changes
  // Foliage
  outCd.rgb = mix(outCd.rgb, candyFoliage * (0.7 + 0.3 * cmLuma), foliageMaskMod * 0.95);
  // Water
  outCd.rgb = mix(outCd.rgb, candyWater * (0.7 + 0.3 * cmLuma), waterMaskMod * 0.8);
  // Blocks
  outCd.rgb = mix(outCd.rgb, outCd.rgb * blockTint, (1.0 - max(foliageMaskMod, waterMaskMod)) * 0.15);
#endif

// Global soft white finish (reduces pop/brightness)
outCd.rgb = mix(outCd.rgb, vec3(0.97), SoftWhiteMix);

// Final composite
	gl_FragData[0] = vec4(outCd.rgb,1.0);
}
#endif
