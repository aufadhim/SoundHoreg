#include "../Sources/AudioDSP.h"
#include <math.h>
#include <stdio.h>
#include <time.h>
static double seconds(void){struct timespec t;clock_gettime(CLOCK_MONOTONIC_RAW,&t);return t.tv_sec+t.tv_nsec*1e-9;}
int main(void){
 float in[1024],out[1024];for(int i=0;i<1024;i++)in[i]=.02f*sinf(i*.1f);
 AudioBufferList input={.mNumberBuffers=1,.mBuffers={{2,sizeof(in),in}}},output={.mNumberBuffers=1,.mBuffers={{2,sizeof(out),out}}};
 for(int eq=0;eq<2;eq++){
  SuaraDSP*s=suara_create();suara_set(s,.22f,0,eq?6:0,eq?-3:0,0,48000);
#ifndef BASELINE
  suara_enable_meter(s,0);
#endif
  for(int i=0;i<100;i++)suara_render(0,0,&input,0,&output,0,s);
  const int iterations=100000;double start=seconds();for(int i=0;i<iterations;i++)suara_render(0,0,&input,0,&output,0,s);double duration=seconds()-start;
  printf("%s: %.3f seconds / %.1f million stereo frames; %.2f ns/frame; checksum=%f\n",eq?"EQ":"flat",duration,iterations*512/1e6,duration*1e9/(iterations*512),out[20]);suara_free(s);
 }
}
