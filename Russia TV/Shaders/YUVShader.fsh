//
//  Shader.fsh
//  TStreamer
//
//  Created by Sergey Seitov on 23.12.10.
//  Copyright 2010 V-Channel. All rights reserved.
//
      
precision mediump float;
varying vec2 v_texCoord;

uniform sampler2D SamplerY;
uniform sampler2D SamplerU;
uniform sampler2D SamplerV;

vec4 yuv2rgb(float Y, float U, float V)
{
  Y = 1.1643 * (Y-0.0625);
  U = U - 0.5;
  V = V - 0.5;

  vec4 v;
  v.r = Y + 1.5958 * V;
  v.g = Y - 0.39173 * U - 0.81290 * V;
  v.b = Y + 2.017 * U;
  v.a = 1.0; 
 
  return v;
}

vec4 texture2DFromYUV2RGB(vec2 v2Tex)
{
	vec2 v2TexUV = v2Tex * 0.5;
	vec4 result = yuv2rgb(texture2D(SamplerY, v2Tex).r,
						  texture2D(SamplerU, v2TexUV).r,
						  texture2D(SamplerV, v2TexUV).r );
	
	return result;
}

void main()
{
	gl_FragColor = texture2DFromYUV2RGB(v_texCoord);
}

