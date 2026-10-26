#include <CoreAudio/CoreAudio.h>
typedef struct SuaraDSP SuaraDSP;
SuaraDSP *suara_create(void);
void suara_free(SuaraDSP *s);
void suara_set(SuaraDSP *s, float gain, float pan, float bass, float treble, int mono, float rate);
float suara_peak(SuaraDSP *s);
void suara_input_channels(SuaraDSP *s, unsigned int channels);
void suara_enable_meter(SuaraDSP *s, int enabled);
unsigned long long suara_callbacks(SuaraDSP *s);
OSStatus suara_render(AudioObjectID device, const AudioTimeStamp *now, const AudioBufferList *input, const AudioTimeStamp *inputTime, AudioBufferList *output, const AudioTimeStamp *outputTime, void *context);
typedef struct AuditStats AuditStats;
AuditStats *audit_stats_create(void);
void audit_stats_free(AuditStats *s);
float audit_stats_peak(AuditStats *s);
double audit_stats_rms(AuditStats *s);
unsigned long long audit_stats_frames(AuditStats *s);
OSStatus audit_render(AudioObjectID d,const AudioTimeStamp*n,const AudioBufferList*in,const AudioTimeStamp*it,AudioBufferList*out,const AudioTimeStamp*ot,void*ctx);
double soundhoreg_cpu_seconds(void);
