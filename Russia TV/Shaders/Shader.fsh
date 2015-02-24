//
//  Shader.fsh
//  TStreamer
//
//  Created by Sergey Seitov on 23.12.10.
//  Copyright 2010 V-Channel. All rights reserved.
//
      
precision mediump float;
varying vec2 v_texCoord;

uniform sampler2D Sampler;

vec4 swap(vec4 frame)
{
	vec4 v;
	v.r = frame.b;
	v.g = frame.g;
	v.b = frame.r;
	v.a = 1.0;
	return v;
}

void main()
{
	gl_FragColor = swap( texture2D(Sampler, v_texCoord));
}
