//
//  Shader.vsh
//  TStreamer
//
//  Created by Sergey Seitov on 23.12.10.
//  Copyright 2010 V-Channel. All rights reserved.
//

attribute vec4 a_position;
attribute mediump vec4 a_texCoord;
varying mediump vec2 v_texCoord;

void main()
{
   gl_Position = a_position;
   v_texCoord = a_texCoord.xy;
}
