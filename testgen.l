
%{
#include <stdio.h>
#include "symtab.h"

void error(char *f, char *s);
void errori(char *f, int i);

#ifdef WIN32
#define DIRSTR "\\"
#define DIRCHAR '\\'
#else
#define DIRSTR "/"
#define DIRCHAR '/'
#endif

static int Make=0;
#define MAXDEPEND 1024
static char *target = NULL;
static char *depend[MAXDEPEND]={NULL};

static void add_string(char **r, char *s)
{ if (*r!=NULL) free(*r);
  *r=malloc(strlen(s)+1);
  if (*r==NULL) error("Out of memory",NULL);
  strcpy(*r,s);
}

static void add_target(char *t)
{ add_string(&target,t);
}

static void add_depend(char *d)
{ int i;
  for (i=0; i<MAXDEPEND; i++)
  { if (depend[i]==NULL)
    { add_string(depend+i,d);
      return;
    }
    else if (strcmp(depend[i],d)==0) return;
  }
  error("Too many depencencies",NULL);
}

static void clear_depend(void)
{ int i;
  for (i=0; i<MAXDEPEND; i++)
  { if (depend[i]==NULL) return;
    free(depend[i]);
    depend[i]=NULL;
  }
}

static void write_depend(void)
{ int i;
  for (i=0; i<MAXDEPEND && depend[i]!=NULL; i++)
  { if (i>0) fprintf(stdout," ");
    fprintf(stdout,"%s",depend[i]);
  }
  fprintf(stdout,"\n");
}


/* Handling parameters */
int argno;
char * param_name(int n)
{ static char name[15];
  sprintf(name,"%d",n);
  return name;
}


/* Handling the include stack */

#define MAX_INCLUDE_DEPTH 10
YY_BUFFER_STATE include_buffers[MAX_INCLUDE_DEPTH];
int include_lines[MAX_INCLUDE_DEPTH+1];
char *include_names[MAX_INCLUDE_DEPTH+1];
int include_stack_ptr = 0;
int current_line=1;
char *current_name="Global";

void include_new(char *name)
{ current_line=1;
  current_name=name;
}

void include_push(void)
{ if ( include_stack_ptr >= MAX_INCLUDE_DEPTH ) error("Includes nested too deeply",NULL);
  include_buffers[include_stack_ptr] = YY_CURRENT_BUFFER;
  include_lines[include_stack_ptr] = current_line;
  include_names[include_stack_ptr] = current_name;
  include_stack_ptr++;
}


int include_pop()
{ if (include_stack_ptr>0)
  { --include_stack_ptr;
    yy_delete_buffer( YY_CURRENT_BUFFER );
    yy_switch_to_buffer(include_buffers[include_stack_ptr]);
    current_line= include_lines[include_stack_ptr];
    current_name= include_names[include_stack_ptr];
    return 1;
  }
  else
    return 0;
}     

/* Utilities */

#define NEXTLINE (current_line++)

void error(char *f, char *s)
{ fprintf(stderr,"ERROR (in %s, line %d):\t",current_name, current_line);
  fprintf(stderr,f,s);
  printf("\n"); /* make sure output ends with a newline */
  exit(1);
}
void errori(char *f, int i)
{ fprintf(stderr,"ERROR (in %s, line %d):\t",current_name, current_line);
  fprintf(stderr,f,i);
  printf("\n"); /* make sure output ends with a newline */
  exit(1);
}

#define MAXPATH 16
char *path[MAXPATH] ={"." DIRSTR,"." DIRSTR "lib" DIRSTR,0};
char pathlen=2;


void add_path(char *str)
{ if (pathlen>=MAXPATH) error("Too many path entries\n",NULL);
  path[pathlen++]=str;
}

void add_dir(char *arg)
{ char *p, *dir, *dirlib;
  int n;
  if (arg == NULL) return;
  p=strrchr(arg,DIRCHAR);
  if (p==NULL) return;
  n=p+1-arg;
  dirlib= malloc(n+1+5); /* path + "/lib/"+'\0' */
  dir= malloc(n+1+1); /* path + "/"+'\0' */
  if (dir==NULL || dirlib==NULL) error("Out of memory",NULL);
  strncpy(dirlib,arg,n);
  dirlib[n]=0;
  strcat(dirlib,"lib" DIRSTR);
  strncpy(dir,arg,n);
  dir[n]=0;
  add_path(dirlib);
  add_path(dir);
}


FILE * file_open(char *filename)
/* try to open the file in the current directory then try the path */
{ FILE *f;
  int i;
  f = fopen(filename,"r");
  if (f==NULL)
  { for (i=0; f==NULL && i<pathlen && path[i]!=NULL; i++)
    { char * name;
      name = malloc(strlen(filename)+strlen(path[i])+1);
      if (name==NULL) error("Out of memory\n",NULL);
      strcpy(name,path[i]);
      strcat(name,filename);
      f = fopen(name,"r");
      if (Make>0 && f!=NULL) add_depend(name);
      free(name);
    }
    if (Make>0 && f==NULL) add_depend(filename);    
    if (Make==0 && f==NULL) error("Unable to open file %s\n",filename);
  }
  else
    if (Make>0) add_depend(filename);
  return f;
}

/* Storing values in a string */

#define MAXDRIVER 30000
char value[MAXDRIVER];
int vsize=0;
int vlevel=0;
node *curvar=NULL;

void start_value(char *name)
{curvar = insert(name);
 vsize=0;
 vlevel=0;
}

void start_global(char *name)
{curvar = insert_global(name);
 vsize=0;
 vlevel=0;
}


void put_value(char *c)
{ while (*c!=0)
  { if (vsize>=MAXDRIVER) error("Driver too long",NULL);
    value[vsize++]=*c++;
  }
}

int end_value(void)
{ if (vsize>=MAXDRIVER) error("Driver too long",NULL);
  value[vsize++]=0;
  set_content(curvar,value,NULL,string); 
}

/* Handling output of the generated code to a file */

FILE *codefile=NULL;
char *codename;
char *codeext="mms"; /* the default extension */
int testno=0;
node *next_input=NULL;
YY_BUFFER_STATE input_buffer = ((YY_BUFFER_STATE)0);

void set_ext(char *ext)
{codeext = ext;
}

void set_code(char *arg)
{ char *p = strrchr(arg,DIRCHAR);
  if (p==NULL)
  { codename=malloc(strlen(arg)+1);
    if (codename==NULL) error("Out of memory\n",NULL);
    strcpy(codename,arg);
  }
  else
  { codename=malloc(strlen(p+1)+1);
    if (codename==NULL) error("Out of memory\n",NULL);
    strcpy(codename,p+1);
  }
}

void closecode(void)
{  if (codefile!=NULL) 
   { fclose(codefile);
     codefile=NULL;
   }
}

void opencode(int n)
{  
#define MAXNAME 1024
   char testname[MAXNAME];
   closecode();
   if (n!=testno) errori("TEST %d unordered\n",n);
   snprintf(testname,MAXNAME,"%d-%s.%s",testno,codename,codeext);
   if (Make==0)
   { codefile = fopen(testname,"w");
     if (codefile==NULL) error("Unable to create test file: %s\n",testname);
   }
   else if (Make > 1)
   { if (target!=NULL)
     { printf("%s: ",target);
       write_depend();
       clear_depend();
     }
     add_target(testname);
   }
}

void putcode(char *c)
{ if (Make==0 && codefile!=NULL) fputs(c,codefile);
}


/* Start and end a Case */
void starttest(int n)
{ if (n<=testno) errori("TEST %d unordered\n",n);
  testno=n;
  scope_open();
  opencode(n);
}

void endtest(int n)
{ if (n!=testno) errori("END %d does not match TEST\n",n);
  scope_close();
  closecode();
}


/* Handling Variables */

void switch_to(node *p)
{ int c;
  switch (p->tag)
  { case undef:  
      error("Variable '%s' is undefined\n",p->symbol);
      break;
    case ref:
      if (p->ptr==NULL) error("Variable '%s' is an undefined reference.\n",p->symbol);
      switch_to((node*)p->ptr);
      break;
    case string:
      if (p->name==NULL) error("Variable '%s' is an undefined string.\n",p->symbol);
      include_push();
      yy_scan_string(p->name);
      include_new(p->symbol);
      break;
    case file:
      if (p->name==NULL) error("Variable '%s' is an undefined file.\n",p->symbol);
      if (p->ptr==NULL)
        p->ptr = file_open(p->name);
      rewind((FILE*)(p->ptr));
      include_push();
      yy_switch_to_buffer(yy_create_buffer((FILE*)(p->ptr), YY_BUF_SIZE));
      include_new(p->name);
      break;
    default:    
      error("Variable '%s' has illegal tag\n",p->symbol);
  }
}


%}

BL    [[:blank:]]
EOL   (\n|\r|\n\r|\r\n)
NUM   [0-9]+
ESC   \[\[
CSE   \]\]
VAR    [a-zA-Z0-9]+

%x SPECIAL SET GLOBAL COMMENT INCLUDE TEST ENDTEST VALUE SKIP ARGSKIP ARGVALUE ARGSTR

%option noyywrap

%%
.                                     putcode(yytext);
\n                                    { if (vlevel!=0) error("Wrong nesting\n",NULL);
                                        putcode(yytext); 
                                        NEXTLINE;
                                      }
{ESC}                                 BEGIN(SPECIAL);

{CSE}                                 error("Extra closing ] ] \n",NULL);

<SPECIAL>COMMENT{BL}*                 BEGIN(COMMENT);
<SPECIAL>{BL}+                        BEGIN(COMMENT);
<SPECIAL>{EOL}                        NEXTLINE; BEGIN(COMMENT);
<SPECIAL>SET{BL}*                     BEGIN(SET);
<SPECIAL>GLOBAL{BL}*                  BEGIN(GLOBAL);
<SPECIAL>INCLUDE{BL}*                 BEGIN(INCLUDE);
<SPECIAL>TEST{BL}*                    BEGIN(TEST);
<SPECIAL>END{BL}*                     BEGIN(ENDTEST);
<SPECIAL>{VAR}                    { next_input = lookup(yytext);
                                         if (next_input==NULL) error("Undefined variable '%s'\n",yytext);
					 scope_open();
					 argno=1;
                                         BEGIN(ARGSKIP);  
                                       }
<COMMENT>.                             ;
<COMMENT>{EOL}                         NEXTLINE;
<COMMENT>{ESC}                         vlevel++;
<COMMENT>{CSE}                         if (--vlevel<0) { vlevel=0; BEGIN(INITIAL); }

<SET>{VAR}                            start_value(yytext); BEGIN(SKIP);
<GLOBAL>{VAR}                         start_global(yytext); BEGIN(SKIP);
<SKIP>{BL}+                           BEGIN(VALUE);
<SKIP>{BL}*{EOL}                         NEXTLINE; BEGIN(VALUE);
<SKIP>.                               error("Illegal character '%s' in variable",yytext);


<VALUE>.                              put_value(yytext);
<VALUE>{EOL}                          put_value(yytext); NEXTLINE;
<VALUE>{ESC}                          put_value(yytext); vlevel++;
<VALUE>{CSE}                          { vlevel--; 
                                        if (vlevel<0)
                                        { end_value();
                                          vlevel=0;
                                          BEGIN(INITIAL);
                                        }
                                        else 
                                          put_value(yytext);
                                      }

<INCLUDE>{BL}+                        ;
<INCLUDE>{EOL}                        NEXTLINE;
<INCLUDE>[^[:space:]\]]+              { FILE *f;
                                        f = file_open(yytext);
                                        if (f!=NULL)
                                        { next_input=insert(yytext);
					  set_content(next_input,yytext,f,file);
                                          scope_open();
					  argno=1;
                                          BEGIN(ARGSKIP);
                                        }
                                        else
                                        {vlevel=0;  BEGIN(COMMENT); }
                                      }

<ARGSKIP>{BL}                        ;
<ARGSKIP>{EOL}                       NEXTLINE;
<ARGSKIP>{CSE}                       switch_to(next_input); BEGIN(INITIAL);
<ARGSKIP>{ESC}                       { start_value(param_name(argno++)); 
                                       vlevel++; 
                                       put_value(yytext);
                                       BEGIN(ARGVALUE);
                                     }
<ARGSKIP>\"                          { start_value(param_name(argno++)); 
                                       put_value(yytext);
                                       BEGIN(ARGSTR);
                                     }
<ARGSKIP>.                           { start_value(param_name(argno++)); 
                                       put_value(yytext);
                                       BEGIN(ARGVALUE);
                                     }

<ARGSTR>\"                           put_value(yytext);BEGIN(ARGVALUE);
<ARGSTR>.                            put_value(yytext);
<ARGSTR>{EOL}                        put_value(yytext); NEXTLINE;

<ARGVALUE>{ESC}                       put_value(yytext); vlevel++;
<ARGVALUE>{CSE}                       { vlevel--; 
                                        if (vlevel<0)
                                        { end_value();
                                          switch_to(next_input);
                                          vlevel=0; 
                                          BEGIN(INITIAL);
                                        }
                                        else 
                                          put_value(yytext);
                                      }


<ARGVALUE>{BL}                       { if (vlevel==0)
                                        { end_value();
                                          BEGIN(ARGSKIP);
                                        }
                                        else 
                                          put_value(yytext);
                                      }  
<ARGVALUE>{EOL}                       {  NEXTLINE;
                                         if (vlevel==0)
                                         { end_value();
                                           BEGIN(ARGSKIP);
                                         }
                                         else 
                                           put_value(yytext);
                                      }  
<ARGVALUE>.                           put_value(yytext);


<TEST>{NUM}+                          starttest(atoi(yytext)); BEGIN(COMMENT);
<ENDTEST>{NUM}+                       endtest(atoi(yytext));  BEGIN(COMMENT);


<TEST,ENDTEST>{BL}                    ;
<TEST,ENDTEST,COMMENT>{CSE}           BEGIN(INITIAL);


<INITIAL><<EOF>>                      { if (include_pop())
                                          scope_close();
                                         else
                                          yyterminate();
                                      }

<SPECIAL,SET,GLOBAL,COMMENT,INCLUDE,TEST,ENDTEST,VALUE,SKIP,ARGSKIP,ARGVALUE>{EOL}     NEXTLINE;
<SPECIAL,SET,GLOBAL,COMMENT,INCLUDE,TEST,ENDTEST,VALUE,SKIP,ARGSKIP,ARGVALUE,ARGSTR>.  error("Unexpected input '%s'\n",yytext);
<COMMENT><<EOF>>                                                                       error("Unexpected end of file in COMMENT\n",NULL);
<VALUE,SKIP><<EOF>>                                                                    error("Unexpected end of file in Variable definition: %s'\n",curvar->symbol);
<SPECIAL,SET,GLOBAL,INCLUDE,TEST,ENDTEST,ARGSKIP,ARGVALUE,ARGSTR><<EOF>>               error("Unexpected end of file\n",NULL);


%%


int main(int argc, char * argv[])
{ FILE *input;
  char *inputname;
  int option = 0;
  while (argc>option+1 && argv[option+1][0]=='-') 
    { option++; 
      if (argv[option][1]=='I') add_path(argv[option]+2);
      else if (argv[option][1]=='X') set_ext(argv[option]+2);
      else if (argv[option][1]=='M') Make++;
      else error("Unknown option %s\n",argv[option]);
    }

  if (argc<2+option)
  { fprintf(stderr, "Usage: testgen [options] file.tst\n"
                    " options: -Ipath       add path to the search path after . and ." DIRSTR "lib\n"
                    "          -Xextension  use this as extension of the outputfile (default mms)\n"
                    "          -M           output a list of all the includefiles\n"
                    "          -M -M        output make rules for all the generated test files\n"
           );
    return 1;
  }
  add_dir(argv[option+1]);
  add_dir(argv[0]);
  set_code(argv[option+1]);
  inputname=argv[option+1]; 
  input =fopen(inputname,"r"); 
  if (input==NULL) error("Unable to open file %s\n",inputname);
  input_buffer = yy_create_buffer( input, YY_BUF_SIZE);
  yy_switch_to_buffer(input_buffer);
  include_new(inputname);
  vlevel=0;
  scope_open();
  yylex();
  scope_close();
  if (Make==1) write_depend();
  return 0;
}

