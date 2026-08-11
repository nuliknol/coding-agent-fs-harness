#include "pbnfc.h"
#include <pthread.h>
#include <stdlib.h>
#include <string.h>
#include <stdatomic.h>
#include <stdio.h>

typedef struct { int rule,dot; size_t origin; } Item;
typedef struct { Item *v; size_t n,cap; } Items;
typedef enum { JOB_CLOSE, JOB_SCAN } Job;
typedef struct { struct Pool *p; int n; } WorkerArg;
struct Pool { pthread_t th[8]; pthread_mutex_t mu; pthread_cond_t kick,done; unsigned gen,finished; bool stop; atomic_bool failed; Job job; const Grammar *g; const MarkTokens *tok; Items *chart; size_t pos,begin,end; Items cand[8]; size_t task[8]; };
static bool push(Items *v,Item x){Item *q;if(v->n==v->cap){size_t c=v->cap?v->cap*2:32;q=realloc(v->v,c*sizeof(*q));if(!q)return false;v->v=q;v->cap=c;}v->v[v->n++]=x;return true;}
static bool matches(const Grammar *g,const Symbol *s,const MarkToken *t){if(s->type==SYM_LITERAL)return strcmp(s->literal,t->text)==0;if(s->type==SYM_KIND){const char *k=g->kinds[s->value];return (strcmp(k,"IDENT")==0&&t->kind==MK_IDENT)||(strcmp(k,"STRING")==0&&t->kind==MK_STRING)||(strcmp(k,"TEXT")==0&&t->kind==MK_TEXT);}return false;}
static void work_close(struct Pool *p,int me){size_t z,i,j;Items *o=&p->cand[me];for(z=p->begin+me;z<p->end;z+=8){Item it=p->chart[p->pos].v[z];Rule *r=&p->g->rules[it.rule];p->task[me]++;if((size_t)it.dot<r->nrhs){Symbol *x=&r->rhs[it.dot];if(x->type==SYM_NONTERM){for(i=0;i<p->g->nrules;i++)if(p->g->rules[i].lhs==x->value&&!push(o,(Item){(int)i,0,p->pos}))atomic_store(&p->failed,true);}}else{for(j=0;j<p->chart[it.origin].n;j++){Item before=p->chart[it.origin].v[j];Rule *br=&p->g->rules[before.rule];if((size_t)before.dot<br->nrhs&&br->rhs[before.dot].type==SYM_NONTERM&&br->rhs[before.dot].value==r->lhs&&!push(o,(Item){before.rule,before.dot+1,before.origin}))atomic_store(&p->failed,true);}}}}
static void work_scan(struct Pool *p,int me){size_t z;Items *o=&p->cand[me];for(z=p->begin+me;z<p->end;z+=8){Item it=p->chart[p->pos].v[z];Rule *r=&p->g->rules[it.rule];p->task[me]++;if((size_t)it.dot<r->nrhs&&r->rhs[it.dot].type!=SYM_NONTERM&&matches(p->g,&r->rhs[it.dot],&p->tok->v[p->pos])&&!push(o,(Item){it.rule,it.dot+1,it.origin}))atomic_store(&p->failed,true);}}
static void *worker(void *arg){WorkerArg *a=arg;struct Pool *p=a->p;int me=a->n;unsigned seen=0;free(a);for(;;){pthread_mutex_lock(&p->mu);while(!p->stop&&seen==p->gen)pthread_cond_wait(&p->kick,&p->mu);if(p->stop){pthread_mutex_unlock(&p->mu);break;}seen=p->gen;pthread_mutex_unlock(&p->mu);if(p->job==JOB_CLOSE)work_close(p,me);else work_scan(p,me);pthread_mutex_lock(&p->mu);if(++p->finished==8)pthread_cond_signal(&p->done);pthread_mutex_unlock(&p->mu);}return NULL;}
Pool *pool_create(Error *e){struct Pool *p=calloc(1,sizeof(*p));int i;if(!p){error_set(e,(Location){0,1,1},"out of memory");return NULL;}atomic_init(&p->failed,false);if(pthread_mutex_init(&p->mu,NULL)||pthread_cond_init(&p->kick,NULL)||pthread_cond_init(&p->done,NULL)){free(p);error_set(e,(Location){0,1,1},"pthread initialization failed");return NULL;}for(i=0;i<8;i++){WorkerArg *a=malloc(sizeof(*a));if(!a){error_set(e,(Location){0,1,1},"out of memory");p->stop=true;break;}a->p=p;a->n=i;if(pthread_create(&p->th[i],NULL,worker,a)){free(a);error_set(e,(Location){0,1,1},"pthread creation failed");p->stop=true;break;}}if(i<8){pthread_mutex_lock(&p->mu);p->stop=true;pthread_cond_broadcast(&p->kick);pthread_mutex_unlock(&p->mu);while(i--)pthread_join(p->th[i],NULL);pthread_cond_destroy(&p->kick);pthread_cond_destroy(&p->done);pthread_mutex_destroy(&p->mu);free(p);return NULL;}return p;}
void pool_destroy(Pool *p){int i;if(!p)return;pthread_mutex_lock(&p->mu);p->stop=true;pthread_cond_broadcast(&p->kick);pthread_mutex_unlock(&p->mu);for(i=0;i<8;i++)pthread_join(p->th[i],NULL);for(i=0;i<8;i++)free(p->cand[i].v);pthread_cond_destroy(&p->kick);pthread_cond_destroy(&p->done);pthread_mutex_destroy(&p->mu);free(p);}
static bool dispatch(Pool *p,Job j,const Grammar *g,const MarkTokens *t,Items *c,size_t pos,size_t begin,size_t end){int i;p->g=g;p->tok=t;p->chart=c;p->pos=pos;p->begin=begin;p->end=end;p->job=j;atomic_store(&p->failed,false);for(i=0;i<8;i++)p->cand[i].n=0;pthread_mutex_lock(&p->mu);p->finished=0;p->gen++;pthread_cond_broadcast(&p->kick);while(p->finished<8)pthread_cond_wait(&p->done,&p->mu);pthread_mutex_unlock(&p->mu);return !atomic_load(&p->failed);}
static int cmp(const void *a,const void *b){const Item *x=a,*y=b;if(x->rule!=y->rule)return x->rule-y->rule;if(x->dot!=y->dot)return x->dot-y->dot;return x->origin<y->origin?-1:x->origin>y->origin;}
static bool merge(Pool *p,Items *dest){Items all={0};size_t i,j,old=dest->n;for(i=0;i<8;i++)for(j=0;j<p->cand[i].n;j++)if(!push(&all,p->cand[i].v[j])){free(all.v);return false;}qsort(all.v,all.n,sizeof(*all.v),cmp);for(i=0;i<all.n;i++)if((i==0||cmp(&all.v[i-1],&all.v[i]))&& !push(dest,all.v[i])){free(all.v);return false;}free(all.v);return dest->n>old;}
static void expected_at(const Grammar *g,const Items *c,char *out,size_t z){size_t i;out[0]=0;for(i=0;i<c->n;i++){Item q=c->v[i];Rule *r=&g->rules[q.rule];if((size_t)q.dot<r->nrhs&&r->rhs[q.dot].type!=SYM_NONTERM){char b[128];Symbol *s=&r->rhs[q.dot];if(s->type==SYM_LITERAL)snprintf(b,sizeof(b),"'%s'",s->literal);else snprintf(b,sizeof(b),"$%s",g->kinds[s->value]);if(!strstr(out,b)){if(out[0])strncat(out,"|",z-strlen(out)-1);strncat(out,b,z-strlen(out)-1);}}}if(!out[0])snprintf(out,z,"valid continuation");}
bool recognize(Pool *p,const Grammar *g,const MarkTokens *t,bool *accepted,size_t *rounds,size_t tasks[8],size_t *reject_at,char *expected,size_t es,Error *e){Items *c;size_t pos,i,start=0;bool ok=true;
    memset(tasks,0,8*sizeof(*tasks)); memset(p->task,0,sizeof(p->task)); *rounds=0; *accepted=false;
    c=calloc(t->n+1,sizeof(*c)); if(!c){error_set(e,(Location){0,1,1},"out of memory");return false;}
    for(i=0;i<g->nrules;i++) if(g->rules[i].lhs==g->start&&!push(&c[0],(Item){(int)i,0,0})){ok=false;break;}
    for(pos=0;ok&&pos<=t->n;pos++){
        start=0;
        while(start<c[pos].n){size_t end=c[pos].n;(*rounds)++;
            if(!dispatch(p,JOB_CLOSE,g,t,c,pos,start,end)||!merge(p,&c[pos])) { if(atomic_load(&p->failed)){ok=false;break;} }
            start=end;
        }
        if(pos<t->n&&c[pos].n){(*rounds)++;
            if(!dispatch(p,JOB_SCAN,g,t,c,pos,0,c[pos].n)||!merge(p,&c[pos+1])) { if(atomic_load(&p->failed)){ok=false;break;} }
        }
    }
    for(i=0;i<8;i++) tasks[i]=p->task[i];
    if(!ok){error_set(e,(Location){0,1,1},"out of memory while recognizing");goto done;}
    for(i=0;i<c[t->n].n;i++){Item q=c[t->n].v[i];Rule *r=&g->rules[q.rule];if(r->lhs==g->start&&q.origin==0&&(size_t)q.dot==r->nrhs){*accepted=true;break;}}
    if(!*accepted){for(pos=t->n;pos>0&&c[pos].n==0;pos--){} *reject_at=pos; expected_at(g,&c[pos],expected,es);}
done:
    for(i=0;i<=t->n;i++) free(c[i].v);
    free(c); return ok;
}
