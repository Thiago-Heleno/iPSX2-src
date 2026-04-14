// SPDX-FileCopyrightText: 2002-2025 PCSX2 Dev Team
// SPDX-License-Identifier: GPL-3.0+

#pragma once

#include "GS.h"
#include "GSRegs.h"

class GSUtil
{
public:
	static const char* GetATSTName(u32 atst);
	static const char* GetAFAILName(u32 afail);

	static GS_PRIM_CLASS GetPrimClass(u32 prim);
	static int GetVertexCount(u32 prim);
	static int GetClassVertexCount(u32 primclass);

	static const u32* HasSharedBitsPtr(u32 dpsm);
	static bool HasSharedBits(u32 spsm, const u32* ptr);
	static bool HasSharedBits(u32 spsm, u32 dpsm);
	static bool HasSharedBits(u32 sbp, u32 spsm, u32 dbp, u32 dpsm);
	static bool HasCompatibleBits(u32 spsm, u32 dpsm);
	static bool HasSameSwizzleBits(u32 spsm, u32 dpsm);
	static u32 GetChannelMask(u32 spsm);
	static u32 GetChannelMask(u32 spsm, u32 fbmsk);

	static GSRendererType GetPreferredRenderer();
};

const char* psm_str(int psm);

// Class that represents an octogonal bounding area with sides at 45 degree increments.
class BoundingOct
{
private:
	GSVector4i bbox0; // Standard bbox.
	GSVector4i bbox1; // Bounding diamond (rotated 45 degrees axes and scaled, so (x, y) becomes (x + y, x - y)).

	// Assumes that v is of the form { x, y, x, y }.
	static GSVector4i Rotate45(const GSVector4i& v)
	{
		const GSVector4i swap = v.yxwz();
		return (v + swap).blend32<0xa>(swap - v);
	}

	BoundingOct(const GSVector4i& bbox0, const GSVector4i& bbox1)
		: bbox0(bbox0)
		, bbox1(bbox1)
	{
	}

public:
	// Initialize to null bounding area.
	BoundingOct()
		: bbox0(GSVector4i(INT_MAX, INT_MAX, INT_MIN, INT_MIN))
		, bbox1(GSVector4i(INT_MAX, INT_MAX, INT_MIN, INT_MIN))
	{
	}

	static BoundingOct FromPoint(GSVector4i v)
	{
		v = v.xyxy();
		return { v, Rotate45(v) };
	}

	// The two inputs are assumed to be diagonally opposite to each other in an axis-aligned quad (i.e. sprite).
	static BoundingOct FromSprite(GSVector4i v0, GSVector4i v1)
	{
		const GSVector4i min = v0.min_i32(v1);
		const GSVector4i max = v0.max_i32(v1);
		const GSVector4i bbox = min.upl64(max);
		const GSVector4i x = GSVector4i::cast(GSVector4::cast(min).xxxx(GSVector4::cast(max)));
		const GSVector4i y = bbox.ywwy();
		return {
			bbox,
			(x + y).blend32<0xa>(x - y),
		};
	}

	BoundingOct Union(GSVector4i v) const
	{
		v = v.xyxy();
		return { bbox0.runion(v), bbox1.runion(Rotate45(v)) };
	}

	BoundingOct Union(const BoundingOct& other) const
	{
		return { bbox0.runion(other.bbox0), bbox1.runion(other.bbox1) };
	}

	BoundingOct UnionSprite(GSVector4i pt0, GSVector4i pt1) const
	{
		return Union(FromSprite(pt0, pt1));
	}

	bool Intersects(const BoundingOct& other) const
	{
		return bbox0.rintersects(other.bbox0) && bbox1.rintersects(other.bbox1);
	}

	BoundingOct FixDegenerate() const
	{
		return {
			bbox0.blend(bbox0 + GSVector4i(0, 0, 1, 1), bbox0.xyxy() == bbox0.zwzw()),
			bbox1.blend(bbox1 + GSVector4i(0, 0, 1, 1), bbox1.xyxy() == bbox1.zwzw()),
		};
	}

	const GSVector4i& ToBBox()
	{
		return bbox0;
	}
};
