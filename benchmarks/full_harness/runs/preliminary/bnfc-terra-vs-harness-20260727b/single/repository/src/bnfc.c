#include "bnfc.h"
#include <ctype.h>
#include <stdarg.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef enum { EOF_T, ID_T, TERM_T, START_T, ASSIGN_T, BAR_T, SEMI_T } TType;
typedef struct { TType type; char *s; size_t line, col; } Token;
typedef struct { const char *s; size_t n, p, line, col; } Lex;
typedef enum { TERM, NONTERM } SType;
typedef struct { SType type; char *s; } Symbol;
typedef struct { Symbol *v; size_t n, cap; } Alt;
typedef struct { char *name; Alt *v; size_t n, cap; } Rule;
typedef struct { char *start; Rule *v; size_t n, cap; } Grammar;
typedef struct { bool bad; size_t line, col; char msg[384]; } Error;

static void err(Error *e, size_t l, size_t c, const char *fmt, ...) {
    va_list ap;
    if (e->bad) return;
    e->bad=true; e->line=l; e->col=c;
    va_start(ap,fmt); (void)vsnprintf(e->msg,sizeof(e->msg),fmt,ap); va_end(ap);
}
static char *dup_n(const char *s,size_t n) { char *p=malloc(n+1U); if(p){memcpy(p,s,n);p[n]='\0';} return p; }
static char *dup_s(const char *s) { return dup_n(s,strlen(s)); }
static bool first(unsigned char c) { return c=='_'||(c>='A'&&c<='Z')||(c>='a'&&c<='z'); }
static bool rest(unsigned char c) { return first(c)||(c>='0'&&c<='9'); }
static void adv(Lex *x) { if(x->p<x->n){if(x->s[x->p]=='\n'){x->line++;x->col=1U;}else x->col++;x->p++;} }
static void tok_free(Token *t) { free(t->s); t->s=NULL; }
static Token next(Lex *x, Error *e) {
    Token t={EOF_T,NULL,x->line,x->col}; size_t b,cap,u; char *out;
    while(x->p<x->n) { unsigned char c=(unsigned char)x->s[x->p]; if(isspace(c)) adv(x); else if(c=='#') while(x->p<x->n&&x->s[x->p]!='\n')adv(x); else break; }
    t.line=x->line;t.col=x->col;
    if(x->p==x->n)return t;
    if(x->p+3U<=x->n&&memcmp(x->s+x->p,"::=",3U)==0){t.type=ASSIGN_T;adv(x);adv(x);adv(x);return t;}
    if(x->s[x->p]=='|'){t.type=BAR_T;adv(x);return t;}
    if(x->s[x->p]==';'){t.type=SEMI_T;adv(x);return t;}
    if(x->s[x->p]=='%'){
        if(x->p+6U<=x->n&&memcmp(x->s+x->p,"%start",6U)==0&&(x->p+6U==x->n||!rest((unsigned char)x->s[x->p+6U]))){t.type=START_T;for(b=0;b<6U;b++)adv(x);return t;}
        err(e,t.line,t.col,"unknown directive or character");return t;
    }
    if(first((unsigned char)x->s[x->p])) { b=x->p;adv(x);while(x->p<x->n&&rest((unsigned char)x->s[x->p]))adv(x);t.type=ID_T;t.s=dup_n(x->s+b,x->p-b);if(!t.s)err(e,t.line,t.col,"out of memory");return t; }
    if(x->s[x->p]=='\''){
        cap=16U;u=0U;out=malloc(cap);if(!out){err(e,t.line,t.col,"out of memory");return t;}adv(x);
        while(x->p<x->n&&x->s[x->p]!='\'') { char ch=x->s[x->p]; if(ch=='\\'){adv(x);if(x->p==x->n||(x->s[x->p]!='\\'&&x->s[x->p]!='\'')){free(out);err(e,t.line,t.col,"invalid terminal escape");return t;}ch=x->s[x->p];} if(ch=='\n'||ch=='\r'){free(out);err(e,t.line,t.col,"unterminated terminal");return t;} if(u+1U>=cap){char *q;cap*=2U;q=realloc(out,cap);if(!q){free(out);err(e,t.line,t.col,"out of memory");return t;}out=q;}out[u++]=ch;adv(x); }
        if(x->p==x->n){free(out);err(e,t.line,t.col,"unterminated terminal");return t;}adv(x);out[u]='\0';t.type=TERM_T;t.s=out;return t;
    }
    err(e,t.line,t.col,"unexpected character '%c'",x->s[x->p]);return t;
}
static bool grow(void **p,size_t *cap,size_t z) { size_t n=*cap?*cap*2U:4U;void *q;if(n<*cap||n>(size_t)-1/z)return false;q=realloc(*p,n*z);if(!q)return false;*p=q;*cap=n;return true; }
static void free_g(Grammar *g) { size_t i,j,k;free(g->start);for(i=0;i<g->n;i++){free(g->v[i].name);for(j=0;j<g->v[i].n;j++){for(k=0;k<g->v[i].v[j].n;k++)free(g->v[i].v[j].v[k].s);free(g->v[i].v[j].v);}free(g->v[i].v);}free(g->v);memset(g,0,sizeof(*g)); }
static bool add_rule(Grammar*g,const char*s,Rule**r){if(g->n==g->cap&&!grow((void**)&g->v,&g->cap,sizeof(*g->v)))return false;*r=&g->v[g->n++];memset(*r,0,sizeof(**r));(*r)->name=dup_s(s);return (*r)->name!=NULL;}
static bool add_alt(Rule*r,Alt**a){if(r->n==r->cap&&!grow((void**)&r->v,&r->cap,sizeof(*r->v)))return false;*a=&r->v[r->n++];memset(*a,0,sizeof(**a));return true;}
static bool add_sym(Alt*a,SType type,const char*s){if(a->n==a->cap&&!grow((void**)&a->v,&a->cap,sizeof(*a->v)))return false;a->v[a->n].type=type;a->v[a->n].s=dup_s(s);if(!a->v[a->n].s)return false;a->n++;return true;}
static bool take(Lex*x,Token*t,Error*e){tok_free(t);*t=next(x,e);return !e->bad;}
static bool parse(const char*s,size_t n,Grammar*g,Error*e){
    Lex x={s,n,0U,1U,1U};Token t=next(&x,e);Rule*r;Alt*a;
    if(e->bad)return false;
    if(t.type!=START_T){err(e,t.line,t.col,"grammar must begin with %%start NAME");goto no;}
    if(!take(&x,&t,e)) goto no;
    if(t.type!=ID_T){err(e,t.line,t.col,"expected start symbol name");goto no;}
    g->start=dup_s(t.s);
    if(!g->start){err(e,t.line,t.col,"out of memory");goto no;}
    if(!take(&x,&t,e)) goto no;
    while(t.type!=EOF_T){if(t.type!=ID_T){err(e,t.line,t.col,"expected rule name");goto no;}if(!add_rule(g,t.s,&r)){err(e,t.line,t.col,"out of memory");goto no;}if(!take(&x,&t,e))goto no;if(t.type!=ASSIGN_T){err(e,t.line,t.col,"expected ::= after rule name");goto no;}if(!take(&x,&t,e))goto no;
        for(;;){if(!add_alt(r,&a)){err(e,t.line,t.col,"out of memory");goto no;}while(t.type==ID_T||t.type==TERM_T){if(!add_sym(a,t.type==ID_T?NONTERM:TERM,t.s)){err(e,t.line,t.col,"out of memory");goto no;}if(!take(&x,&t,e))goto no;}if(t.type==BAR_T){if(a->n==0U){err(e,t.line,t.col,"empty alternative must be final");goto no;}if(!take(&x,&t,e))goto no;continue;}if(t.type==SEMI_T){if(!take(&x,&t,e))goto no;break;}err(e,t.line,t.col,"expected symbol, |, or ;");goto no;}
    }tok_free(&t);return true;
no:tok_free(&t);return false;
}
static ptrdiff_t index_of(const Grammar*g,const char*s){size_t i;for(i=0;i<g->n;i++)if(strcmp(g->v[i].name,s)==0)return (ptrdiff_t)i;return -1;}
static bool names(const Grammar*g,const char*start,Error*e){size_t i,j,k;if(g->n==0U){err(e,0,0,"grammar has no rules");return false;}if(index_of(g,start)<0){err(e,0,0,"start symbol '%s' is not defined",start);return false;}for(i=0;i<g->n;i++){for(j=0;j<i;j++)if(strcmp(g->v[i].name,g->v[j].name)==0){err(e,0,0,"duplicate rule '%s'",g->v[i].name);return false;}for(j=0;j<g->v[i].n;j++)for(k=0;k<g->v[i].v[j].n;k++)if(g->v[i].v[j].v[k].type==NONTERM&&index_of(g,g->v[i].v[j].v[k].s)<0){err(e,0,0,"undefined nonterminal '%s'",g->v[i].v[j].v[k].s);return false;}}return true;}
static bool left_rec(const Grammar*g,Error*e){
    size_t n=g->n,i,j,k;bool *nul=calloc(n,sizeof(*nul)),*edge=calloc(n*n,sizeof(*edge)),change=true;unsigned char *color=calloc(n,sizeof(*color));
    if(!nul||!edge||!color){free(nul);free(edge);free(color);err(e,0,0,"out of memory");return false;}
    while(change){change=false;for(i=0;i<n;i++)for(j=0;j<g->v[i].n;j++){bool empty=true;for(k=0;k<g->v[i].v[j].n;k++){Symbol*z=&g->v[i].v[j].v[k];if(z->type==TERM||!nul[(size_t)index_of(g,z->s)]){empty=false;break;}}if(empty&&!nul[i]){nul[i]=true;change=true;}}}
    for(i=0;i<n;i++)for(j=0;j<g->v[i].n;j++)for(k=0;k<g->v[i].v[j].n&&g->v[i].v[j].v[k].type==NONTERM;k++){size_t q=(size_t)index_of(g,g->v[i].v[j].v[k].s);edge[i*n+q]=true;if(!nul[q])break;}
    for(i=0;i<n;i++)if(!color[i]){size_t *st=malloc(n*sizeof(*st)),*at=calloc(n,sizeof(*at)),d=0U;if(!st||!at){free(st);free(at);free(nul);free(edge);free(color);err(e,0,0,"out of memory");return false;}st[d++]=i;color[i]=1U;while(d){size_t v=st[d-1U],q;while(at[d-1U]<n&&!edge[v*n+at[d-1U]])at[d-1U]++;if(at[d-1U]==n){color[v]=2U;d--;continue;}q=at[d-1U]++;if(color[q]==1U){err(e,0,0,"left recursion involving '%s'",g->v[q].name);free(st);free(at);free(nul);free(edge);free(color);return false;}if(!color[q]){st[d++]=q;color[q]=1U;}}free(st);free(at);}
    free(nul);free(edge);free(color);return true;
}
static char **tokens_of(const char*s,size_t *count,Error*e){char **v=NULL;size_t n=0U,cap=0U,p=0U,len=strlen(s);while(p<len){size_t b;char*q;while(p<len&&isspace((unsigned char)s[p]))p++;if(p==len)break;b=p;while(p<len&&!isspace((unsigned char)s[p]))p++;q=dup_n(s+b,p-b);if(!q||(n==cap&&!grow((void**)&v,&cap,sizeof(*v)))){free(q);while(n)free(v[--n]);free(v);err(e,0,0,"out of memory");return NULL;}v[n++]=q;}*count=n;return v;}
static void free_tokens(char**v,size_t n){while(n)free(v[--n]);free(v);}
static bool recognize(const Grammar*g,const char*start,char**tok,size_t m,Error*e){
    size_t n=g->n,w=m+1U,cells,i,a,from;bool *rel,*changedp;bool changed=true;ptrdiff_t si=index_of(g,start);
    if(n&&w>(size_t)-1/w/n){err(e,0,0,"input is too large");return false;}cells=n*w*w;rel=calloc(cells,sizeof(*rel));if(!rel){err(e,0,0,"out of memory");return false;}
    while(changed){changed=false;for(i=0;i<n;i++)for(a=0;a<g->v[i].n;a++)for(from=0;from<=m;from++){Alt *alt=&g->v[i].v[a];bool *pos=calloc(w,sizeof(*pos)),*nxt=calloc(w,sizeof(*nxt));size_t s,p,q;if(!pos||!nxt){free(pos);free(nxt);free(rel);err(e,0,0,"out of memory");return false;}pos[from]=true;for(s=0;s<alt->n;s++){Symbol*z=&alt->v[s];memset(nxt,0,w*sizeof(*nxt));for(p=0;p<=m;p++)if(pos[p]){if(z->type==TERM){if(p<m&&strcmp(tok[p],z->s)==0)nxt[p+1U]=true;}else{size_t r=(size_t)index_of(g,z->s);for(q=0;q<=m;q++)if(rel[(r*w+p)*w+q])nxt[q]=true;}}{bool *tmp=pos;pos=nxt;nxt=tmp;}}for(p=0;p<=m;p++)if(pos[p]&&!rel[(i*w+from)*w+p]){rel[(i*w+from)*w+p]=true;changed=true;}free(pos);free(nxt);}}
    changedp=&rel[((size_t)si*w)*w+m];i=*changedp;free(rel);return i!=0U;
}
static char *read_all(const char*path,size_t*n,Error*e){FILE*f=fopen(path,"rb");long z;char*s;if(!f){err(e,0,0,"cannot open grammar '%s'",path);return NULL;}if(fseek(f,0,SEEK_END)||((z=ftell(f))<0)||fseek(f,0,SEEK_SET)){fclose(f);err(e,0,0,"cannot read grammar '%s'",path);return NULL;}s=malloc((size_t)z+1U);if(!s||fread(s,1U,(size_t)z,f)!=(size_t)z){free(s);fclose(f);err(e,0,0,"cannot read grammar '%s'",path);return NULL;}fclose(f);s[z]='\0';*n=(size_t)z;return s;}
static void report(const Error*e){if(e->line)printf("GRAMMAR_ERROR line=%zu col=%zu %s\n",e->line,e->col,e->msg);else printf("GRAMMAR_ERROR %s\n",e->msg);}
int main(int ac,char**av){const char*path=NULL,*input=NULL,*chosen=NULL,*start;char*source=NULL;char**tok=NULL;size_t len=0U,nt=0U;Grammar g={0};Error e={0};int i;
    for(i=1;i<ac;i++){const char**dst=NULL;if(!strcmp(av[i],"--grammar"))dst=&path;else if(!strcmp(av[i],"--input"))dst=&input;else if(!strcmp(av[i],"--start"))dst=&chosen;else{err(&e,0,0,"unknown command-line option '%s'",av[i]);break;}if(++i>=ac||*dst){err(&e,0,0,"missing or repeated option value");break;}*dst=av[i];}
    if(!e.bad&&(!path||!input)) err(&e,0,0,"usage: bnfc --grammar PATH --input TEXT [--start NAME]");
    if(!e.bad) source=read_all(path,&len,&e);
    if(!e.bad) parse(source,len,&g,&e);
    start=chosen?chosen:g.start;
    if(!e.bad) names(&g,start,&e);
    if(!e.bad) left_rec(&g,&e);
    if(!e.bad) tok=tokens_of(input,&nt,&e);
    if(e.bad){report(&e);free(source);free_g(&g);free_tokens(tok,nt);return 2;}
    if(recognize(&g,start,tok,nt,&e)){printf("ACCEPT start=%s tokens=%zu\n",start,nt);free(source);free_g(&g);free_tokens(tok,nt);return 0;}
    if(e.bad){report(&e);free(source);free_g(&g);free_tokens(tok,nt);return 2;}
    printf("REJECT offset=0 expected=terminal\n");free(source);free_g(&g);free_tokens(tok,nt);return 1;
}
