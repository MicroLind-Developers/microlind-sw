; -----------------------------------------------------------------
; Swedish PETSCII character ROM data for the MOS 8568 VDC driver
; -----------------------------------------------------------------
; petscii-swe.bin contains two 2 KiB character sets:
;   $0000-$07FF  uppercase/graphics, normal and inverse glyphs
;   $0800-$0FFF  lowercase/uppercase, normal and inverse glyphs
;
; Each source glyph is eight bytes. The VDC uses a sixteen-byte stride, so
; the upload routine expands the selected glyphs as it copies them. Only the
; normal 128-glyph half of the second set is embedded to conserve BIOS ROM.

VDC_PETSCII_LOWERCASE_NORMAL:
    includebin "../resources/petscii-swe.bin",$0800,$0400
