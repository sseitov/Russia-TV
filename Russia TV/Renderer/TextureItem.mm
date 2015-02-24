//
//  TextureItem.mm
//  vTV
//
//  Created by Sergey Seitov on 20.01.14.
//  Copyright (c) 2014 V-Channel. All rights reserved.
//

#include "TextureItem.h"

static GLfloat gVertices[] = {
	-1.0f,  1.0f, 0.0f,		// Position 0
	0.0f,  0.0f,			// TexCoord 0
	-1.0f, -1.0f, 0.0f,		// Position 1
	0.0f,  1.0f,			// TexCoord 1
	1.0f, -1.0f, 0.0f,		// Position 2
	1.0f,  1.0f,			// TexCoord 2
	1.0f,  1.0f, 0.0f,		// Position 3
	1.0f,  0.0f				// TexCoord 3
};

GLfloat PTSTexture::ratio()
{
	return (size.width+1)/(size.height+1);
}

BGRA::BGRA(GLint sampler) : _sampler(sampler)
{
	glGenTextures(1, &_bgra);
}

BGRA::~BGRA()
{
	glDeleteTextures(1, &_bgra);
}

GLfloat* BGRA::vertices()
{
	return gVertices;
}

void BGRA::activate(int)
{
	glActiveTexture ( GL_TEXTURE0);
	glBindTexture ( GL_TEXTURE_2D, _bgra);
}

void BGRA::create(AVFrame* frame)
{
	size = CGSizeMake(frame->width, frame->height);
	
	glBindTexture ( GL_TEXTURE_2D, _bgra );
	glUniform1i ( _sampler, 0 );
	glTexParameteri ( GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR );
	glTexParameteri ( GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR );
	glTexParameteri ( GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE );
	glTexParameteri ( GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE );
	glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, size.width, size.height, 0, GL_RGBA, GL_UNSIGNED_BYTE, NULL);
}

void BGRA::update(AVFrame* frame)
{
	glBindTexture ( GL_TEXTURE_2D, _bgra);
	glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, size.width, size.height, GL_RGBA, GL_UNSIGNED_BYTE, frame->data[0]);
	pts = frame->pts;
}

//============================================================================================

YUV::YUV(GLint* samplers) : _offset(1.0)
{
	for (int i=0; i < 3; i++) {
		_samplers[i] = samplers[i];
	}
	glGenTextures(3, _planes);
	memcpy(_vertices, gVertices, 20*sizeof(GLfloat));
}

YUV::~YUV()
{
	glDeleteTextures(3, _planes);
}

GLfloat* YUV::vertices()
{
	_vertices[13] =_vertices[18] = _offset;
	return _vertices;
}

void YUV::activate(int plane)
{
	glActiveTexture ( GL_TEXTURE0+plane);
	glBindTexture ( GL_TEXTURE_2D, _planes[plane]);
}

void YUV::create(AVFrame* frame)
{
	size = CGSizeMake(frame->width, frame->height);
	
	glBindTexture ( GL_TEXTURE_2D, _planes[0] );
	glUniform1i ( _samplers[0], 0 );
	glTexImage2D(GL_TEXTURE_2D, 0, GL_LUMINANCE, frame->linesize[0], size.height, 0, GL_LUMINANCE, GL_UNSIGNED_BYTE, NULL);
	glTexParameteri ( GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR );
	glTexParameteri ( GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR );
	glTexParameteri ( GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE );
	glTexParameteri ( GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE );
	
	glBindTexture ( GL_TEXTURE_2D, _planes[1] );
	glUniform1i ( _samplers[1], 1 );
	glTexImage2D(GL_TEXTURE_2D, 0, GL_LUMINANCE, frame->linesize[0], size.height, 0, GL_LUMINANCE, GL_UNSIGNED_BYTE, NULL);
	glTexParameteri ( GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR );
	glTexParameteri ( GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR );
	glTexParameteri ( GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE );
	glTexParameteri ( GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE );
	
	glBindTexture ( GL_TEXTURE_2D, _planes[2] );
	glUniform1i ( _samplers[2], 2 );
	glTexImage2D(GL_TEXTURE_2D, 0, GL_LUMINANCE, frame->linesize[0], size.height, 0, GL_LUMINANCE, GL_UNSIGNED_BYTE, NULL);
	glTexParameteri ( GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR );
	glTexParameteri ( GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR );
	glTexParameteri ( GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE );
	glTexParameteri ( GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE );
	
	if (frame->linesize[0] > 0) {
		_offset = (GLfloat)frame->width / (GLfloat)frame->linesize[0] - 0.001f;
	}
}

void YUV::update(AVFrame* frame)
{
	glBindTexture ( GL_TEXTURE_2D, _planes[0]);
	glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, frame->linesize[0], size.height, GL_LUMINANCE, GL_UNSIGNED_BYTE, frame->data[0]);
	
	glBindTexture ( GL_TEXTURE_2D, _planes[1]);
	glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, frame->linesize[1], size.height/2, GL_LUMINANCE, GL_UNSIGNED_BYTE, frame->data[1]);
	
	glBindTexture ( GL_TEXTURE_2D, _planes[2]);
	glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, frame->linesize[2], size.height/2, GL_LUMINANCE, GL_UNSIGNED_BYTE, frame->data[2]);
	
	pts = frame->pts;
}
