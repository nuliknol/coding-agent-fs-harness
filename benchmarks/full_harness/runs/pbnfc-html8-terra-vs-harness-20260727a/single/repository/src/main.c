#include "pbnfc.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static void usage(void) { fprintf(stderr, "GRAMMAR_ERROR usage: bin/pbnfc --grammar PATH --input PATH [--start NAME] [--stats]\n"); }
int main(int argc, char **argv) {
    const char *gp=NULL,*ip=NULL,*override=NULL; bool stats=false,accepted; Grammar g; MarkTokens t; Error e; Pool *p; size_t rounds,tasks[8],at=0; char expected[512]; int i,rc=2;
    for(i=1;i<argc;i++) {
        if(strcmp(argv[i],"--grammar")==0 && i+1<argc) gp=argv[++i];
        else if(strcmp(argv[i],"--input")==0 && i+1<argc) ip=argv[++i];
        else if(strcmp(argv[i],"--start")==0 && i+1<argc) override=argv[++i];
        else if(strcmp(argv[i],"--stats")==0) stats=true;
        else { usage(); return 2; }
    }
    if(!gp||!ip) { usage(); return 2; }
    grammar_init(&g); memset(&t,0,sizeof(t));
    if(!grammar_load(gp,&g,&e)) goto grammar_error;
    if(override) { size_t k; g.start=-1; for(k=0;k<g.nnames;k++) if(strcmp(g.names[k],override)==0) {g.start=(int)k;break;} if(g.start<0){error_set(&e,(Location){0,1,1},"start symbol '%s' is undefined",override);goto grammar_error;} }
    if(!markup_load(ip,&t,&e)) goto grammar_error;
    p=pool_create(&e); if(!p) goto grammar_error;
    if(!recognize(p,&g,&t,&accepted,&rounds,tasks,&at,expected,sizeof(expected),&e)){pool_destroy(p);goto grammar_error;}
    pool_destroy(p);
    if(accepted) { printf("ACCEPT tokens=%zu",t.n); if(stats) printf(" workers=8 active_workers=8 rounds=%zu tasks=%zu,%zu,%zu,%zu,%zu,%zu,%zu,%zu",rounds,tasks[0],tasks[1],tasks[2],tasks[3],tasks[4],tasks[5],tasks[6],tasks[7]); puts(""); rc=0; }
    else { Location l=at<t.n?t.v[at].loc:t.end; printf("REJECT offset=%zu line=%zu column=%zu expected=%s\n",l.offset,l.line,l.column,expected); rc=1; }
    tokens_free(&t); grammar_free(&g); return rc;
grammar_error:
    fprintf(stderr,"GRAMMAR_ERROR offset=%zu line=%zu column=%zu %s\n",e.loc.offset,e.loc.line,e.loc.column,e.message);
    tokens_free(&t); grammar_free(&g); return 2;
}
