// SPDX-FileCopyrightText: 2002-2025 PCSX2 Dev Team
// SPDX-License-Identifier: GPL-3.0+

#include "GSRendererNull.h"

GSRendererNull::GSRendererNull() = default;

void GSRendererNull::VSync(u32 field, bool registers_written, bool idle_frame)
{
	GSRenderer::VSync(field, registers_written, idle_frame);

	m_draw_transfers.clear();
}

void GSRendererNull::Draw()
{
}

GSTexture* GSRendererNull::GetOutput(int i, float& scale, int& y_offset)
{
	// [iter253] Null renderer 使用verifyprobe
	{
		static u32 s_null_go = 0;
		if (s_null_go < 5) {
			fprintf(stderr, "@@NULL_GETOUTPUT@@ n=%u i=%d *** NULL RENDERER ACTIVE ***\n", s_null_go++, i);
		}
	}
	return nullptr;
}
