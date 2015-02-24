//
//  TextureItem.h
//  vTV
//
//  Created by Sergey Seitov on 20.01.14.
//  Copyright (c) 2014 V-Channel. All rights reserved.
//

#ifndef __vTV__TextureItem__
#define __vTV__TextureItem__

#import <GLKit/GLKit.h>

extern "C" {
#	include "libavcodec/avcodec.h"
#	include "libavformat/avformat.h"
#	include <libswscale/swscale.h>
};

class PTSTexture
{
public:
	int64_t pts;
	CGSize size;
	
	PTSTexture() : pts(AV_NOPTS_VALUE), size(CGSizeZero) {}
	virtual ~PTSTexture() {}
	
	GLfloat ratio();
	
	virtual int numPlanes() = 0;
	virtual GLfloat* vertices() = 0;
	virtual void activate(int plane) = 0;
	virtual void create(AVFrame*) = 0;
	virtual void update(AVFrame*) = 0;
};

class BGRA : public PTSTexture
{
	GLuint _bgra;
	GLint _sampler;
	
public:
	
	BGRA(GLint sampler);
	virtual ~BGRA();
	
	virtual int numPlanes() { return 1; }
	virtual GLfloat* vertices();
	virtual void activate(int plane);
	virtual void create(AVFrame*);
	virtual void update(AVFrame*);
};

struct YUV : public PTSTexture
{
	GLuint _planes[3];
	GLint _samplers[3];
	GLfloat _offset;
	GLfloat	_vertices[20];
public:
	
	YUV(GLint* samplers);
	virtual ~YUV();
			
	virtual int numPlanes() { return 3; }
	virtual GLfloat* vertices();
	virtual void activate(int plane);
	virtual void create(AVFrame*);
	virtual void update(AVFrame*);
};

#endif /* defined(__vTV__TextureItem__) */
