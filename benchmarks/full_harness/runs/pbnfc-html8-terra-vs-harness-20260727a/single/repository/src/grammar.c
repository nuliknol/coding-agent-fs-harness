#include "pbnfc.h"
#include <ctype.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef enum { GT_EOF, GT_START, GT_TOKEN, GT_ID, GT_DOLLAR, GT_STR, GT_DEF, GT_BAR, GT_SEMI, GT_BAD } GType;
typedef struct { GType type; char *s; Location loc; } GToken;
typedef struct { const char *s; size_t n, i; Location loc; Error *err; } GLex;

static void *grow(void *p, size_t *cap, size_t need, size_t unit) {
    size_t nc; void *q;
    if (need <= *cap) return p;
    nc = *cap ? *cap * 2 : 16;
    if (nc < need || nc > SIZE_MAX / unit) return NULL;
    q = realloc(p, nc * unit); if (!q) return NULL; *cap = nc; return q;
}
static char *dup_range(const char *s, size_t n) { char *p = malloc(n + 1); if (!p) return NULL; memcpy(p,s,n); p[n]='\0'; return p; }
static void step(GLex *l) { unsigned char c=(unsigned char)l->s[l->i++]; l->loc.offset++; if(c=='\n'){l->loc.line++;l->loc.column=1;}else l->loc.column++; }
static void skip(GLex *l) { while(l->i<l->n){ char c=l->s[l->i]; if(isspace((unsigned char)c)){step(l);continue;} if(c=='#'){while(l->i<l->n&&l->s[l->i]!='\n')step(l);continue;} break;} }
static bool ident0(unsigned char c) { return isalpha(c)||c=='_'; }
static bool identc(unsigned char c) { return isalnum(c)||c=='_'; }
static GToken next(GLex *l) {
    GToken t; size_t b; char c; t.s=NULL; skip(l); t.loc=l->loc;
    if(l->i==l->n){t.type=GT_EOF;return t;} c=l->s[l->i];
    if(c=='%' && l->i+6<=l->n && strncmp(l->s+l->i,"%start",6)==0 && (l->i+6==l->n||isspace((unsigned char)l->s[l->i+6]))) { l->i+=6;l->loc.offset+=6;l->loc.column+=6;t.type=GT_START;return t; }
    if(c=='%' && l->i+6<=l->n && strncmp(l->s+l->i,"%token",6)==0 && (l->i+6==l->n||isspace((unsigned char)l->s[l->i+6]))) { l->i+=6;l->loc.offset+=6;l->loc.column+=6;t.type=GT_TOKEN;return t; }
    if(c==':'&&l->i+2<l->n&&l->s[l->i+1]==':'&&l->s[l->i+2]=='='){step(l);step(l);step(l);t.type=GT_DEF;return t;}
    if(c=='|'){step(l);t.type=GT_BAR;return t;} if(c==';'){step(l);t.type=GT_SEMI;return t;}
    if(c=='$'){ step(l); b=l->i; if(!ident0((unsigned char)l->s[l->i])){t.type=GT_BAD;return t;} while(l->i<l->n&&identc((unsigned char)l->s[l->i]))step(l); t.s=dup_range(l->s+b,l->i-b);t.type=GT_DOLLAR;return t; }
    if(ident0((unsigned char)c)){b=l->i;while(l->i<l->n&&identc((unsigned char)l->s[l->i]))step(l);t.s=dup_range(l->s+b,l->i-b);t.type=GT_ID;return t;}
    if(c=='\''){ size_t cap=16,len=0; char *p=malloc(cap); step(l); if(!p){t.type=GT_BAD;return t;} while(l->i<l->n&&l->s[l->i]!='\''){char x=l->s[l->i]; if(x=='\\'){step(l);if(l->i==l->n||(l->s[l->i]!='\\'&&l->s[l->i]!='\'')){free(p);t.type=GT_BAD;return t;}x=l->s[l->i];} if(len+2>cap){char *q=realloc(p,cap*2);if(!q){free(p);t.type=GT_BAD;return t;}p=q;cap*=2;}p[len++]=x;step(l);} if(l->i==l->n){free(p);t.type=GT_BAD;return t;}step(l);p[len]='\0';t.s=p;t.type=GT_STR;return t; }
    step(l); t.type=GT_BAD; return t;
}
static void tokfree(GToken *t){free(t->s);t->s=NULL;}
static int find(char **v,size_t n,const char *s){size_t i;for(i=0;i<n;i++)if(strcmp(v[i],s)==0)return (int)i;return -1;}
static bool name_add(Grammar *g,char *s,Error *e,Location l){char **q;if(find(g->names,g->nnames,s)>=0){error_set(e,l,"duplicate rule '%s'",s);return false;}q=grow(g->names,&g->names_cap,g->nnames+1,sizeof(*q));if(!q){error_set(e,l,"out of memory");return false;}g->names=q;g->names[g->nnames++]=s;return true;}
static bool kind_add(Grammar *g,char *s,Error *e,Location l){char **q;if(find(g->kinds,g->nkinds,s)>=0){error_set(e,l,"duplicate token kind '%s'",s);return false;}q=grow(g->kinds,&g->kinds_cap,g->nkinds+1,sizeof(*q));if(!q){error_set(e,l,"out of memory");return false;}g->kinds=q;g->kinds[g->nkinds++]=s;return true;}
static bool rule_add(Grammar *g,Rule r,Error *e,Location l){Rule *q=grow(g->rules,&g->rules_cap,g->nrules+1,sizeof(*q));if(!q){error_set(e,l,"out of memory");return false;}g->rules=q;g->rules[g->nrules++]=r;return true;}
void grammar_init(Grammar *g){memset(g,0,sizeof(*g));g->start=-1;}
void grammar_free(Grammar *g){size_t i,j;for(i=0;i<g->nnames;i++)free(g->names[i]);for(i=0;i<g->nkinds;i++)free(g->kinds[i]);for(i=0;i<g->nrules;i++){for(j=0;j<g->rules[i].nrhs;j++)free(g->rules[i].rhs[j].literal);free(g->rules[i].rhs);}free(g->names);free(g->kinds);free(g->rules);grammar_init(g);}
static bool readfile(const char *path,char **s,size_t *n,Error *e){FILE *f=fopen(path,"rb");long z;if(!f){error_set(e,(Location){0,1,1},"cannot open '%s'",path);return false;}if(fseek(f,0,SEEK_END)|| (z=ftell(f))<0 || fseek(f,0,SEEK_SET)){fclose(f);error_set(e,(Location){0,1,1},"cannot read '%s'",path);return false;}*s=malloc((size_t)z+1);if(!*s){fclose(f);error_set(e,(Location){0,1,1},"out of memory");return false;}if(fread(*s,1,(size_t)z,f)!=(size_t)z){free(*s);fclose(f);error_set(e,(Location){0,1,1},"cannot read '%s'",path);return false;}fclose(f);(*s)[z]=0;*n=(size_t)z;return true;}
static bool leftrec(const Grammar *g,Error *e){size_t n=g->nnames,i,j,k,iter;bool *nullable=calloc(n,sizeof(*nullable)),*edge=calloc(n*n,sizeof(*edge));if(!nullable||!edge){free(nullable);free(edge);error_set(e,(Location){0,1,1},"out of memory");return false;}for(iter=0;iter<=n;iter++){bool ch=false;for(i=0;i<g->nrules;i++){Rule *r=&g->rules[i];bool ok=true;for(j=0;j<r->nrhs;j++){Symbol *s=&r->rhs[j];if(s->type!=SYM_NONTERM||!nullable[s->value]){ok=false;break;}}if(ok&&!nullable[r->lhs]){nullable[r->lhs]=true;ch=true;}}if(!ch)break;}for(i=0;i<g->nrules;i++){Rule *r=&g->rules[i];for(j=0;j<r->nrhs;j++){Symbol *s=&r->rhs[j];if(s->type!=SYM_NONTERM)break;edge[(size_t)r->lhs*n+s->value]=true;if(!nullable[s->value])break;}}for(k=0;k<n;k++)for(i=0;i<n;i++)if(edge[i*n+k])for(j=0;j<n;j++)if(edge[k*n+j])edge[i*n+j]=true;for(i=0;i<n;i++)if(edge[i*n+i]){error_set(e,(Location){0,1,1},"left recursion involving '%s'",g->names[i]);free(nullable);free(edge);return false;}free(nullable);free(edge);return true;}
bool grammar_load(const char *path,Grammar *g,Error *e){char *s;size_t n;GLex l;GToken t;bool ok=true;grammar_init(g);if(!readfile(path,&s,&n,e))return false;l=(GLex){s,n,0,{0,1,1},e};t=next(&l);if(t.type!=GT_START){error_set(e,t.loc,"first directive must be %%start NAME");ok=false;goto done;}tokfree(&t);t=next(&l);if(t.type!=GT_ID){error_set(e,t.loc,"expected start rule name");ok=false;goto done;}g->start=-2;char *start=t.s;t.s=NULL;tokfree(&t);t=next(&l);
while(t.type==GT_TOKEN){tokfree(&t);t=next(&l);if(t.type!=GT_ID||!kind_add(g,t.s,e,t.loc)){if(t.type==GT_ID)t.s=NULL;ok=false;goto done;}t.s=NULL;tokfree(&t);t=next(&l);}while(t.type!=GT_EOF){GToken lhs=t;Rule r;int rule_lhs;size_t rcap=0;memset(&r,0,sizeof(r));if(lhs.type!=GT_ID){error_set(e,lhs.loc,"expected rule name");ok=false;goto done;}if(!name_add(g,lhs.s,e,lhs.loc)){lhs.s=NULL;tokfree(&lhs);ok=false;goto done;}r.lhs=(int)g->nnames-1;rule_lhs=r.lhs;lhs.s=NULL;tokfree(&lhs);t=next(&l);if(t.type!=GT_DEF){error_set(e,t.loc,"expected ::= after rule name");ok=false;goto done;}tokfree(&t);t=next(&l);for(;;){while(t.type==GT_ID||t.type==GT_DOLLAR||t.type==GT_STR){Symbol x;Symbol *q;memset(&x,0,sizeof(x));if(t.type==GT_ID){x.type=SYM_NONTERM;x.literal=t.s;t.s=NULL;}else if(t.type==GT_DOLLAR){x.type=SYM_KIND;x.literal=t.s;t.s=NULL;}else{x.type=SYM_LITERAL;x.literal=t.s;t.s=NULL;}q=grow(r.rhs,&rcap,r.nrhs+1,sizeof(*q));if(!q){free(x.literal);error_set(e,t.loc,"out of memory");ok=false;goto rulefail;}r.rhs=q;r.rhs[r.nrhs++]=x;tokfree(&t);t=next(&l);}if(!rule_add(g,r,e,t.loc)){ok=false;goto rulefail;}memset(&r,0,sizeof(r));r.lhs=rule_lhs;rcap=0;if(t.type==GT_BAR){tokfree(&t);t=next(&l);continue;}if(t.type==GT_SEMI){tokfree(&t);t=next(&l);break;}error_set(e,t.loc,"expected '|', ';', or grammar symbol");ok=false;goto done;rulefail: {size_t q;for(q=0;q<r.nrhs;q++)free(r.rhs[q].literal);free(r.rhs);goto done;}}}
g->start=find(g->names,g->nnames,start);if(g->start<0){error_set(e,(Location){0,1,1},"start symbol '%s' is undefined",start);ok=false;}free(start);if(!ok)goto done;for(size_t a=0;a<g->nrules;a++)for(size_t b=0;b<g->rules[a].nrhs;b++){Symbol *x=&g->rules[a].rhs[b];int v=find(x->type==SYM_KIND?g->kinds:g->names,x->type==SYM_KIND?g->nkinds:g->nnames,x->literal);if(x->type==SYM_LITERAL)continue;if(v<0){error_set(e,(Location){0,1,1},"undefined %s '%s'",x->type==SYM_KIND?"token kind":"symbol",x->literal);ok=false;break;}x->value=v;free(x->literal);x->literal=NULL;}if(ok)ok=leftrec(g,e);
done: tokfree(&t);free(s);if(!ok){if(g->start==-2)free(start);grammar_free(g);}return ok;}
