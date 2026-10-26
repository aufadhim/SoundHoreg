#include "AudioDSP.h"
#include <stdatomic.h>
#include <stdlib.h>
#include <math.h>
#include <string.h>
struct SuaraDSP { _Atomic float gain, pan, bass, treble, rate, peak; _Atomic int mono; _Atomic unsigned long long callbacks; float smooth, low[2], highLow[2]; };
SuaraDSP *suara_create(void) { SuaraDSP *s=calloc(1,sizeof(*s)); if(s){s->gain=1;s->rate=48000;s->smooth=1;}return s; }
void suara_free(SuaraDSP *s){free(s);}
void suara_set(SuaraDSP *s,float gain,float pan,float bass,float treble,int mono,float rate){atomic_store(&s->gain,gain);atomic_store(&s->pan,pan);atomic_store(&s->bass,bass);atomic_store(&s->treble,treble);atomic_store(&s->mono,mono);atomic_store(&s->rate,rate);}
float suara_peak(SuaraDSP *s){return atomic_exchange(&s->peak,0);}
unsigned long long suara_callbacks(SuaraDSP *s){return atomic_load(&s->callbacks);}
OSStatus suara_render(AudioObjectID d,const AudioTimeStamp*n,const AudioBufferList*in,const AudioTimeStamp*it,AudioBufferList*out,const AudioTimeStamp*ot,void*ctx){
 SuaraDSP*s=ctx; if(!s)return noErr; atomic_fetch_add(&s->callbacks,1);
 for(UInt32 b=0;b<out->mNumberBuffers;b++)if(out->mBuffers[b].mData)memset(out->mBuffers[b].mData,0,out->mBuffers[b].mDataByteSize);
 if(!in->mNumberBuffers||!out->mNumberBuffers)return noErr;
 // Tap channels follow the physical device's inputs in the aggregate.
 UInt32 last=in->mNumberBuffers-1;
 const AudioBuffer *a=&in->mBuffers[last];
 int planar=a->mNumberChannels==1 && last>0 && in->mBuffers[last-1].mNumberChannels==1;
 const AudioBuffer *l=planar?&in->mBuffers[last-1]:a;
 if(!l->mData||!a->mData||l->mNumberChannels==0||a->mNumberChannels==0)return noErr;
 UInt32 frames=l->mDataByteSize/(sizeof(float)*l->mNumberChannels);
 if(planar && a->mDataByteSize/sizeof(float)<frames)frames=a->mDataByteSize/sizeof(float);
 for(UInt32 b=0;b<out->mNumberBuffers;b++){if(out->mBuffers[b].mNumberChannels==0)return noErr;UInt32 f=out->mBuffers[b].mDataByteSize/(sizeof(float)*out->mBuffers[b].mNumberChannels);if(f<frames)frames=f;}
 float target=atomic_load(&s->gain),pan=atomic_load(&s->pan),bass=powf(10,atomic_load(&s->bass)/20)-1,treble=powf(10,atomic_load(&s->treble)/20)-1;
 if(atomic_load(&s->callbacks)==1)s->smooth=target;
 float rate=atomic_load(&s->rate),lo=1-expf(-2*M_PI*200/rate),hi=1-expf(-2*M_PI*4000/rate),peak=0;int mono=atomic_load(&s->mono);
 for(UInt32 f=0;f<frames;f++){
  float v[2];v[0]=((float*)l->mData)[f*l->mNumberChannels];v[1]=planar?((float*)a->mData)[f]:((float*)l->mData)[f*l->mNumberChannels+(l->mNumberChannels>1?1:0)];
  for(int c=0;c<2;c++)if(!isfinite(v[c]))v[c]=0;
  if(mono)v[0]=v[1]=(v[0]+v[1])*.5f;
  s->smooth+=(target-s->smooth)*.003f;
  for(int c=0;c<2;c++){s->low[c]+=lo*(v[c]-s->low[c]);s->highLow[c]+=hi*(v[c]-s->highLow[c]);v[c]=(v[c]+bass*s->low[c]+treble*(v[c]-s->highLow[c]))*s->smooth*(c==0?(pan>0?1-pan:1):(pan<0?1+pan:1));if(!isfinite(v[c]))v[c]=0;v[c]=fmaxf(-1,fminf(1,v[c]));peak=fmaxf(peak,fabsf(v[c]));}
  if(out->mBuffers[0].mNumberChannels>=2){float*p=out->mBuffers[0].mData;if(p){p[f*out->mBuffers[0].mNumberChannels]=v[0];p[f*out->mBuffers[0].mNumberChannels+1]=v[1];}}
  else if(out->mNumberBuffers>=2){if(out->mBuffers[0].mData)((float*)out->mBuffers[0].mData)[f]=v[0];if(out->mBuffers[1].mData)((float*)out->mBuffers[1].mData)[f]=v[1];}
  else if(out->mBuffers[0].mData)((float*)out->mBuffers[0].mData)[f]=(v[0]+v[1])*.5f;
 }
 atomic_store(&s->peak,peak);return noErr;
}
struct AuditStats { _Atomic double squares; _Atomic unsigned long long frames; _Atomic float peak; };
AuditStats*audit_stats_create(void){return calloc(1,sizeof(AuditStats));}
void audit_stats_free(AuditStats*s){free(s);}
float audit_stats_peak(AuditStats*s){return atomic_load(&s->peak);}
unsigned long long audit_stats_frames(AuditStats*s){return atomic_load(&s->frames);}
double audit_stats_rms(AuditStats*s){unsigned long long n=atomic_load(&s->frames);return n?sqrt(atomic_load(&s->squares)/n):0;}
OSStatus audit_render(AudioObjectID d,const AudioTimeStamp*n,const AudioBufferList*in,const AudioTimeStamp*it,AudioBufferList*out,const AudioTimeStamp*ot,void*ctx){
 for(UInt32 b=0;b<out->mNumberBuffers;b++)if(out->mBuffers[b].mData)memset(out->mBuffers[b].mData,0,out->mBuffers[b].mDataByteSize);
 if(!in->mNumberBuffers)return 0;const AudioBuffer*b=&in->mBuffers[in->mNumberBuffers-1];if(!b->mData||!b->mNumberChannels)return 0;
 AuditStats*s=ctx;double sum=0;float peak=atomic_load(&s->peak);UInt32 frames=b->mDataByteSize/(4*b->mNumberChannels);float*p=b->mData;
 for(UInt32 f=0;f<frames;f++){float v=p[f*b->mNumberChannels];sum+=(double)v*v;peak=fmaxf(peak,fabsf(v));}
 atomic_fetch_add(&s->squares,sum);atomic_fetch_add(&s->frames,frames);atomic_store(&s->peak,peak);return 0;
}
