%{
/* $Id$ */
#include <ctype.h>
#include "base/gmisc.h"
#include "base/gstream.h"
#include "base/glist.h"
#include "math/rational.h"
#include "nfg.h"
#include "nfplayer.h"
#include "nfstrat.h"

static gInput *infile;
static gText last_name;  
static gNumber last_number;
static gText title, comment;  
static Nfg *N; 
static int ncont, pl, cont;
static gList<gText> names;
static gList<gNumber> numbers; 
static gList<gText> stratnames;
static NFOutcome *outcome; 

static bool CreateNfg(const gList<gText> &, const gList<gNumber> &,
	              const gList<gText> &);
static void SetPayoff(int cont, int pl, const gNumber &);

void nfg_yyerror(char *);
int nfg_yylex(void);

%}

%token LBRACE
%token RBRACE
%token SLASH
%token NAME
%token VARNAME
%token NUMBER

%%

nfgfile:      header 
              { if (!CreateNfg(names, numbers, stratnames))  return 1;
		names.Flush();  numbers.Flush();  stratnames.Flush();
	        N->SetTitle(title); N->SetComment(comment);
              }              
              body  { return 0; }

header:       NAME { title = last_name; pl = 0; }  playerlist 
              stratlist commentopt
 
playerlist:   LBRACE players RBRACE

players:      player
       |      players player

player:       NAME   { names.Append(last_name); }

stratlist:    dimensionality
         |    stratnamelist

stratnamelist:  LBRACE playerstrlist RBRACE

playerstrlist:   playerstrats
             |   playerstrlist playerstrats

playerstrats:  LBRACE { pl++; numbers.Append(0); } stratnames RBRACE

stratnames:   stratname
          |   stratnames stratname

stratname:    NAME  { stratnames.Append(last_name); numbers[pl] += 1; }

commentopt:
          |   NAME   { comment = last_name; }


dimensionality:   LBRACE intlist RBRACE

intlist:      integer
       |      intlist integer

integer:      NUMBER  { numbers.Append(last_number); }

body:         payoffbody | outcomebody


payoffbody:         { cont = 1;
                pl = 1; }
              payofflist

payofflist:   payoff
          |   payofflist payoff

payoff:       NUMBER
                {  if (pl > N->NumPlayers())   {
		    cont++;
		    pl = 1;
		  }	
		if (cont > ncont)  YYERROR;
		SetPayoff(cont, pl, last_number);
		pl++;
	      }

outcomebody:   outcomelist { cont = 1; } contingencylist

outcomelist:   LBRACE RBRACE
           |   LBRACE outcomes RBRACE

outcomes:      outcome
        |      outcomes outcome

outcome:       LBRACE NAME
                 { outcome = N->NewOutcome();
                   outcome->SetName(last_name);  pl = 1; }
               outcpaylist RBRACE

outcpaylist:   outcpay
           |   outcpaylist commaopt outcpay

outcpay:       NUMBER   
                 { if (pl > N->NumPlayers())  YYERROR;
                   N->SetPayoff(outcome, pl++, last_number);  }
 
commaopt:    | ','   


contingencylist:  contingency
               |  contingencylist contingency

contingency:   NUMBER
                { if (cont > ncont)  YYERROR;
                  if (last_number != gNumber(0)) {
                    N->SetOutcome(cont++, N->Outcomes()[last_number]); 
                  }
                  else  {
                    N->SetOutcome(cont++, 0);
                  }
                }
              
%%

void nfg_yyerror(char *)    { }

int nfg_yylex(void)
{
  char c, d;

  while (1)  {
    do  {
      *infile >> c;
    }  while (isspace(c));
 
    if (c == '/')   {
      *infile >> d;
      if (d == '/')  {
	do  {
	  *infile >> d;
	}  while (d != '\n');
      }
      else if (d == '*')  {
	int done = 0;
	while (!done)  {
	  do {
	    *infile >> d;
	  }  while (d != '*');
	  *infile >> d;
	  if (d == '/')   done = 1;
	}
      }
      else  {
	infile->unget(d);
	return SLASH;
      }
    }
    else
      break;
  }

  if (isalpha(c))   {
    last_name = c;
    *infile >> c;
    while (isalpha(c))   {
      last_name += c;
      *infile >> c;
    }  
    infile->unget(c);
    return VARNAME;
  }   

  if (c == '"')  {
    infile->unget(c);
    *infile >> last_name;

    return NAME;
  }
  else if (isdigit(c) || c == '-')   {
    infile->unget(c);
    *infile >> last_number;
    return NUMBER;
  }
  
  switch (c)   {
    case '-':  *infile >> c;
               if (isdigit(c))  {
                 infile->unget(c);
                 *infile >> last_number;
		 last_number = -last_number;
                 return NUMBER;
               }
               else  {
                 infile->unget(c);
                 return '-';
               }
    case '{':  return LBRACE;
    case '}':  return RBRACE;
    default:   return c;
  }
}

bool CreateNfg(const gList<gText> &players,
	       const gList<gNumber> &dims,
	       const gList<gText> &strats)
{
  if (players.Length() != dims.Length())   return false;

  gArray<int> dim(dims.Length());
  ncont = 1;
  int i;
  for (i = 1; i <= dim.Length(); i++)  {
    dim[i] = (int) dims[i];
    ncont *= dim[i];
    if (dim[i] <= 0)   return false;
  }
  
  N = new Nfg(dim);
  int strat = 1;
  for (i = 1; i <= dim.Length(); i++)  {
    N->Players()[i]->SetName(players[i]);
    if (strats.Length() > 0)
      for (int j = 1; j <= dim[i]; j++)
	N->Strategies(i)[j]->SetName(strats[strat++]);
  }

  return true;
}

void SetPayoff(int cont, int pl, const gNumber &value)
{
  if (pl == 1)
    N->SetOutcome(cont, N->NewOutcome());
  N->SetPayoff(N->GetOutcome(cont), pl, value);
}

static int ParseNfgFile(void)
{
  infile->seekp(0);
  static char *prologue = { "NFG 1 " };
  char c;
  for (unsigned int i = 0; i < strlen(prologue); i++)  {
    infile->get(c);
    if (c != prologue[i])  return 1;
  }

  infile->get(c);
  switch (c)   {
    case 'D':
      break;
    case 'R':
      break;
    default:
      return 1;
  }

  int ret = nfg_yyparse();
  N->SetIsDirty(false);
  return ret;	
}


int ReadNfgFile(gInput &p_file, Nfg *&p_nfg)
{
  assert(!p_nfg);

  infile = &p_file;
  N = p_nfg;

  if (ParseNfgFile())   {
    if (p_nfg)   { delete p_nfg;  p_nfg = 0; }
    return 0;
  }

  p_nfg = N;
  return 1;
}
