/* More members than the struct-body parser's old fixed 64 (glibc 2.42's
   tcp_info has 69), ending in tcp_info's own bit-field run. */
#include <stdint.h>
struct cd_wide {
  uint8_t m0;
  uint32_t m1;
  uint64_t m2;
  uint16_t m3;
  uint8_t m4;
  uint32_t m5;
  uint64_t m6;
  uint16_t m7;
  uint8_t m8;
  uint32_t m9;
  uint64_t m10;
  uint16_t m11;
  uint8_t m12;
  uint32_t m13;
  uint64_t m14;
  uint16_t m15;
  uint8_t m16;
  uint32_t m17;
  uint64_t m18;
  uint16_t m19;
  uint8_t m20;
  uint32_t m21;
  uint64_t m22;
  uint16_t m23;
  uint8_t m24;
  uint32_t m25;
  uint64_t m26;
  uint16_t m27;
  uint8_t m28;
  uint32_t m29;
  uint64_t m30;
  uint16_t m31;
  uint8_t m32;
  uint32_t m33;
  uint64_t m34;
  uint16_t m35;
  uint8_t m36;
  uint32_t m37;
  uint64_t m38;
  uint16_t m39;
  uint8_t m40;
  uint32_t m41;
  uint64_t m42;
  uint16_t m43;
  uint8_t m44;
  uint32_t m45;
  uint64_t m46;
  uint16_t m47;
  uint8_t m48;
  uint32_t m49;
  uint64_t m50;
  uint16_t m51;
  uint8_t m52;
  uint32_t m53;
  uint64_t m54;
  uint16_t m55;
  uint8_t m56;
  uint32_t m57;
  uint64_t m58;
  uint16_t m59;
  uint8_t m60;
  uint32_t m61;
  uint64_t m62;
  uint16_t m63;
  uint8_t m64;
  uint32_t m65;
  uint32_t b0:2,
		b1:2,
		b2:4,
		b3:24;
  uint64_t last;
};
