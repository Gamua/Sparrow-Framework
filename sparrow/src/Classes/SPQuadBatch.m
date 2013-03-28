//
//  SPQuadBatch.m
//  Sparrow
//
//  Created by Daniel Sperl on 01.03.13.
//  Copyright 2013 Gamua. All rights reserved.
//
//  This program is free software; you can redistribute it and/or modify
//  it under the terms of the Simplified BSD License.
//

#import "SPQuadBatch.h"
#import "SPTexture.h"
#import "SPImage.h"
#import "SPRenderSupport.h"
#import "SPQuadEffect.h"
#import "SPDisplayObjectContainer.h"
#import "SPMacros.h"

#import <GLKit/GLKit.h>

@implementation SPQuadBatch
{
    int _numQuads;
    BOOL _syncRequired;
    
    SPTexture *_texture;
    BOOL _premultipliedAlpha;
    BOOL _tinted;
    
    SPQuadEffect *_quadEffect;
    SPVertexData *_vertexData;
    uint _vertexBufferName;
    ushort *_indexData;
    uint _indexBufferName;
}

@synthesize numQuads = _numQuads;
@synthesize tinted = _tinted;
@synthesize texture = _texture;
@synthesize premultipliedAlpha = _premultipliedAlpha;

- (id)initWithCapacity:(int)capacity
{
    if ((self = [super init]))
    {
        _numQuads = 0;
        _syncRequired = NO;
        _vertexData = [[SPVertexData alloc] init];
        _quadEffect = [[SPQuadEffect alloc] init];

        if (capacity > 0)
            self.capacity = capacity;
    }
    
    return self;
}

- (id)init
{
    return [self initWithCapacity:0];
}

- (void)dealloc
{
    free(_indexData);
    
    glDeleteBuffers(1, &_vertexBufferName);
    glDeleteBuffers(1, &_indexBufferName);
}

- (void)reset
{
    _numQuads = 0;
    _texture = nil;
    _syncRequired = YES;
}

- (void)expand
{
    int oldCapacity = self.capacity;
    self.capacity = oldCapacity < 8 ? 16 : oldCapacity * 2;
}

- (int)capacity
{
    return _vertexData.numVertices / 4;
}

- (void)setCapacity:(int)newCapacity
{
    int oldCapacity = self.capacity;
    int numVertices = newCapacity * 4;
    int numIndices  = newCapacity * 6;
    
    _vertexData.numVertices = numVertices;
    
    if (!_indexData) _indexData = malloc(sizeof(ushort) * numIndices);
    else             _indexData = realloc(_indexData, sizeof(ushort) * numIndices);
    
    // TODO: check that loop is not entered when we're getting smaller
    
    for (int i=oldCapacity; i<newCapacity; ++i)
    {
        _indexData[i*6  ] = i*4;
        _indexData[i*6+1] = i*4 + 1;
        _indexData[i*6+2] = i*4 + 2;
        _indexData[i*6+3] = i*4 + 1;
        _indexData[i*6+4] = i*4 + 3;
        _indexData[i*6+5] = i*4 + 2;
    }
    
    [self createBuffers];
}

- (void)createBuffers
{
    int numVertices = _vertexData.numVertices;
    int numIndices = numVertices / 4 * 6;
    
    if (_vertexBufferName) glDeleteBuffers(1, &_vertexBufferName);
    if (_indexBufferName)  glDeleteBuffers(1, &_indexBufferName);
    if (numVertices == 0)  return;
    
    glGenBuffers(1, &_vertexBufferName);
    glGenBuffers(1, &_indexBufferName);
    
    if (!_vertexBufferName || !_indexBufferName)
        [NSException raise:SP_EXC_DATA_INVALID format:@"could not create vertex buffers"];
    
    glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, _indexBufferName);
    glBufferData(GL_ELEMENT_ARRAY_BUFFER, sizeof(ushort) * numIndices, _indexData, GL_STATIC_DRAW);
    
    _syncRequired = YES;
}

- (void)syncBuffers
{
    if (!_vertexBufferName)
        [self createBuffers];
    
    // don't use 'glBufferSubData'! It's much slower than uploading
    // everything via 'glBufferData', at least on the iPad 1.
    
    glBindBuffer(GL_ARRAY_BUFFER, _vertexBufferName);
    glBufferData(GL_ARRAY_BUFFER, sizeof(SPVertex) * _vertexData.numVertices,
                 _vertexData.vertices, GL_STATIC_DRAW);
    
    _syncRequired = NO;
}

- (void)addQuad:(SPQuad *)quad
{
    [self addQuad:quad alpha:quad.alpha matrix:nil];
}

- (void)addQuad:(SPQuad *)quad alpha:(float)alpha
{
    [self addQuad:quad alpha:alpha matrix:nil];
}

- (void)addQuad:(SPQuad *)quad alpha:(float)alpha matrix:(SPMatrix *)matrix
{
    if (!matrix) matrix = quad.transformationMatrix;
    if (_numQuads + 1 > self.capacity) [self expand];
    if (_numQuads == 0)
    {
        _texture = quad.texture;
        _premultipliedAlpha = quad.premultipliedAlpha;
        [_vertexData setPremultipliedAlpha:_premultipliedAlpha updateVertices:NO];
    }
    
    int vertexID = _numQuads * 4;
    
    [quad copyVertexDataTo:_vertexData atIndex:vertexID];
    [_vertexData transformVerticesWithMatrix:matrix atIndex:vertexID numVertices:4];
    
    if (alpha != 1.0f)
        [_vertexData scaleAlphaBy:alpha atIndex:vertexID numVertices:4];
    
    if (!_tinted)
        _tinted = alpha != 1.0f || quad.tinted;
    
    _syncRequired = YES;
    _numQuads++;
}

- (void)addQuadBatch:(SPQuadBatch *)quadBatch
{
    [self addQuadBatch:quadBatch alpha:quadBatch.alpha matrix:nil];
}

- (void)addQuadBatch:(SPQuadBatch *)quadBatch alpha:(float)alpha
{
    [self addQuadBatch:quadBatch alpha:alpha matrix:nil];
}

- (void)addQuadBatch:(SPQuadBatch *)quadBatch alpha:(float)alpha matrix:(SPMatrix *)matrix
{
    int vertexID = _numQuads * 4;
    int numQuads = quadBatch.numQuads;
    int numVertices = numQuads * 4;
    
    if (!matrix) matrix = quadBatch.transformationMatrix;
    if (_numQuads + numQuads > self.capacity) [self expand];
    if (_numQuads == 0)
    {
        _texture = quadBatch.texture;
        _premultipliedAlpha = quadBatch.premultipliedAlpha;
        [_vertexData setPremultipliedAlpha:_premultipliedAlpha updateVertices:NO];
    }
    
    [quadBatch->_vertexData copyToVertexData:_vertexData atIndex:vertexID numVertices:numVertices];
    [_vertexData transformVerticesWithMatrix:matrix atIndex:vertexID numVertices:numVertices];
    
    if (alpha != 1.0f)
        [_vertexData scaleAlphaBy:alpha atIndex:vertexID numVertices:numVertices];
    
    if (!_tinted)
        _tinted = alpha != 1.0f || quadBatch.tinted;
    
    _syncRequired = YES;
    _numQuads += numQuads;
}

- (BOOL)isStateChangeWithTinted:(BOOL)tinted texture:(SPTexture *)texture alpha:(float)alpha
             premultipliedAlpha:(BOOL)pma numQuads:(int)numQuads
{
    if (_numQuads == 0) return NO;
    else if (_numQuads + numQuads > 8192) return YES; // maximum buffer size
    else if (!_texture && !texture) return _premultipliedAlpha != pma;
    else if (_texture && texture)
        return _tinted != (tinted || alpha != 1.0f) ||
               _texture.name != texture.name ||
               _texture.repeat != texture.repeat ||
               _texture.smoothing != texture.smoothing;
    else return YES;
}

- (SPRectangle *)boundsInSpace:(SPDisplayObject *)targetSpace
{
    SPMatrix *matrix = targetSpace == self ? nil : [self transformationMatrixToSpace:targetSpace];
    return [_vertexData boundsAfterTransformation:matrix atIndex:0 numVertices:_numQuads*4];
}

- (void)render:(SPRenderSupport *)support
{
    if (_numQuads)
    {
        [support finishQuadBatch];
        [support addDrawCalls:1];
        [self renderWithAlpha:support.alpha matrix:support.mvpMatrix];
    }
}

- (void)renderWithAlpha:(float)alpha matrix:(SPMatrix *)matrix
{
    if (!_numQuads) return;
    if (_syncRequired) [self syncBuffers];
    
    _quadEffect.texture = _texture;
    _quadEffect.premultipliedAlpha = _premultipliedAlpha;
    _quadEffect.mvpMatrix = matrix;
    _quadEffect.useTinting = _tinted || alpha != 1.0f;
    _quadEffect.alpha = alpha;
    
    [_quadEffect prepareToDraw];

    if (_premultipliedAlpha) glBlendFunc(GL_ONE, GL_ONE_MINUS_SRC_ALPHA);
    else                     glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
    
    int attribPosition  = _quadEffect.attribPosition;
    int attribColor     = _quadEffect.attribColor;
    int attribTexCoords = _quadEffect.attribTexCoords;
    
    glEnableVertexAttribArray(attribPosition);
    glEnableVertexAttribArray(attribColor);
    
    if (_texture)
        glEnableVertexAttribArray(attribTexCoords);
    
    glBindBuffer(GL_ARRAY_BUFFER, _vertexBufferName);
    glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, _indexBufferName);
    
    glVertexAttribPointer(attribPosition, 2, GL_FLOAT, GL_FALSE, sizeof(SPVertex),
                          (void *)(offsetof(SPVertex, position)));
    
    glVertexAttribPointer(attribColor, 4, GL_UNSIGNED_BYTE, GL_TRUE, sizeof(SPVertex),
                          (void *)(offsetof(SPVertex, color)));
    
    if (_texture)
    {
        glVertexAttribPointer(attribTexCoords, 2, GL_FLOAT, GL_FALSE, sizeof(SPVertex),
                              (void *)(offsetof(SPVertex, texCoords)));
    }
    
    int numIndices = _numQuads * 6;
    glDrawElements(GL_TRIANGLES, numIndices, GL_UNSIGNED_SHORT, 0);
}

+ (id)quadBatch
{
    return [[self alloc] init];
}

#pragma mark - compilation (for flattened sprites)

+ (NSMutableArray *)compileObject:(SPDisplayObject *)object
{
    return [self compileObject:object intoArray:nil];
}

+ (NSMutableArray *)compileObject:(SPDisplayObject *)object intoArray:(NSMutableArray *)quadBatches
{
    if (!quadBatches) quadBatches = [[NSMutableArray alloc] init];
    
    [self compileObject:object intoArray:quadBatches atPosition:-1
             withMatrix:[SPMatrix matrixWithIdentity] alpha:1.0f];

    return quadBatches;
}

+ (int)compileObject:(SPDisplayObject *)object intoArray:(NSMutableArray *)quadBatches
          atPosition:(int)quadBatchID withMatrix:(SPMatrix *)transformationMatrix
               alpha:(float)alpha
{
    BOOL isRootObject = NO;
    float objectAlpha = object.alpha;
    
    SPQuad *quad = [object isKindOfClass:[SPQuad class]] ? (SPQuad *)object : nil;
    SPQuadBatch *batch = [object isKindOfClass:[SPQuadBatch class]] ? (SPQuadBatch *)object :nil;
    SPDisplayObjectContainer *container = [object isKindOfClass:[SPDisplayObjectContainer class]] ?
                                          (SPDisplayObjectContainer *)object : nil;
    if (quadBatchID == -1)
    {
        isRootObject = YES;
        quadBatchID = 0;
        objectAlpha = 1.0f;
        if (quadBatches.count == 0) [quadBatches addObject:[SPQuadBatch quadBatch]];
        else [quadBatches[0] reset];
    }
    
    if (container)
    {
        SPDisplayObjectContainer *container = (SPDisplayObjectContainer *)object;
        SPMatrix *childMatrix = [SPMatrix matrixWithIdentity];
        
        for (SPDisplayObject *child in container)
        {
            if ([child hasVisibleArea])
            {
                [childMatrix copyFromMatrix:transformationMatrix];
                [childMatrix prependMatrix:child.transformationMatrix];
                quadBatchID = [self compileObject:child intoArray:quadBatches atPosition:quadBatchID
                                       withMatrix:childMatrix alpha:alpha * objectAlpha];
            }
        }
    }
    else if (quad || batch)
    {
        SPTexture *texture = [(id)object texture];
        BOOL tinted = [(id)object tinted];
        BOOL pma = [(id)object premultipliedAlpha];
        int numQuads = batch ? batch.numQuads : 1;
        
        SPQuadBatch *currentBatch = quadBatches[quadBatchID];
        
        if ([currentBatch isStateChangeWithTinted:tinted texture:texture alpha:alpha * objectAlpha
                               premultipliedAlpha:pma numQuads:numQuads])
        {
            quadBatchID++;
            if (quadBatches.count <= quadBatchID) [quadBatches addObject:[SPQuadBatch quadBatch]];
            currentBatch = quadBatches[quadBatchID];
            [currentBatch reset];
        }
        
        if (quad)
            [currentBatch addQuad:quad alpha:alpha * objectAlpha matrix:transformationMatrix];
        else
            [currentBatch addQuadBatch:batch alpha:alpha * objectAlpha matrix:transformationMatrix];
    }
    else
    {
        [NSException raise:SP_EXC_INVALID_OPERATION format:@"Unsupported display object: %@",
                                                           [object class]];
    }
    
    if (isRootObject)
    {
        // remove unused batches
        for (int i=quadBatches.count-1; i>quadBatchID; --i)
            [quadBatches removeLastObject];
    }
    
    return quadBatchID;
}

@end
