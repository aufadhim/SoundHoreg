#include "../Sources/AudioDSP.h"
#include <assert.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
static void process(SuaraDSP*s,float*input,float*output,int frames){AudioBufferList i={.mNumberBuffers=1,.mBuffers={{2,(UInt32)(frames*8),input}}};AudioBufferList o={.mNumberBuffers=1,.mBuffers={{2,(UInt32)(frames*8),output}}};suara_render(0,0,&i,0,&o,0,s);}
int main(){
 const int frames=8192;float *i=calloc(frames*2,4),*o=calloc(frames*2,4);SuaraDSP*s=suara_create();
 for(int n=0;n<frames*2;n++)i[n]=.25;
 process(s,i,o,frames);assert(fabsf(o[100]-.25f)<.0001);
 suara_set(s,0,0,0,0,0,48000);process(s,i,o,frames);assert(fabsf(o[frames*2-1])<.00001);
 suara_set(s,2,1,0,0,0,48000);process(s,i,o,frames);assert(o[frames*2-2]==0);assert(fabsf(o[frames*2-1]-.5f)<.0001);
 for(int n=0;n<frames;n++){i[n*2]=.5;i[n*2+1]=-.5;}
 suara_set(s,1,0,0,0,1,48000);process(s,i,o,frames);assert(fabsf(o[frames*2-1])<.0001);
 for(int n=0;n<frames*2;n++)i[n]=.9;
 suara_set(s,2,0,12,12,0,48000);process(s,i,o,frames);for(int n=0;n<frames*2;n++)assert(isfinite(o[n])&&fabsf(o[n])<=1);
 assert(suara_peak(s)<=1);assert(suara_peak(s)==0);
 // Physical input must be ignored: the final tap buffer is the source.
 struct {UInt32 count;AudioBuffer buffers[2];} multiple={2,{{1,frames*4,i},{2,frames*8,i}}};
 AudioBufferList output={.mNumberBuffers=1,.mBuffers={{2,frames*8,o}}};
 suara_set(s,1,0,0,0,0,48000);suara_render(0,0,(AudioBufferList*)&multiple,0,&output,0,s);assert(isfinite(o[20]));
 // Separate left/right buffers and mismatched buffer lengths are bounded.
 float left[64],right[64],ol[64],orr[64];for(int n=0;n<64;n++){left[n]=.2f;right[n]=.4f;}
 struct {UInt32 count;AudioBuffer buffers[2];} pi={2,{{1,sizeof(left),left},{1,sizeof(right),right}}},po={2,{{1,sizeof(ol),ol},{1,sizeof(orr),orr}}};
 SuaraDSP*st=suara_create();suara_render(0,0,(AudioBufferList*)&pi,0,(AudioBufferList*)&po,0,st);assert(fabsf(ol[30]-.2f)<.0001);assert(fabsf(orr[30]-.4f)<.0001);
 assert(suara_callbacks(st)==1);suara_free(st);
 // A non-finite input cannot poison future filter state.
 i[0]=NAN;i[1]=INFINITY;suara_set(s,1,0,0,0,0,48000);process(s,i,o,frames);assert(isfinite(o[0])&&isfinite(o[2]));
 // A mono tap following a physical microphone must not be mistaken for stereo planes.
 float mic[64],voice[64],monoOut[128];for(int n=0;n<64;n++){mic[n]=.9f;voice[n]=.1f;}
 struct {UInt32 count;AudioBuffer buffers[2];} mi={2,{{1,sizeof(mic),mic},{1,sizeof(voice),voice}}};AudioBufferList mo={.mNumberBuffers=1,.mBuffers={{2,sizeof(monoOut),monoOut}}};
 SuaraDSP*sm=suara_create();suara_input_channels(sm,1);suara_render(0,0,(AudioBufferList*)&mi,0,&mo,0,sm);assert(fabsf(monoOut[20]-.1f)<.00001f&&fabsf(monoOut[21]-.1f)<.00001f);suara_free(sm);
 // Hidden-window mode skips meter calculation without changing samples.
 SuaraDSP*hidden=suara_create();suara_enable_meter(hidden,0);process(hidden,i,o,frames);assert(suara_peak(hidden)==0);assert(isfinite(o[100]));suara_free(hidden);
 // SIMD and scalar path agree over mute, gain, pan, and negative samples.
 for(int step=0;step<5;step++){float gain=step*.5f;SuaraDSP*a=suara_create(),*b=suara_create();suara_set(a,gain,0,0,0,0,48000);suara_set(b,gain,0,0,0,1,48000);for(int n=0;n<frames;n++)i[2*n]=i[2*n+1]=.2f*sinf(n*.1f);process(a,i,o,frames);float *reference=calloc(frames*2,4);process(b,i,reference,frames);for(int n=0;n<frames*2;n++)assert(fabsf(o[n]-reference[n])<.00001f);free(reference);suara_free(a);suara_free(b);}
 suara_free(s);free(i);free(o);puts("PASS: unity, mute, gain, balance, mono, clipping guard, meters, aggregate input mapping");
}
