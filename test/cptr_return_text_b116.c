const unsigned char *value_text(void*);

const char *errmsg(void *db){
  const char *z;
  if( !db ){
    return "no db";
  }
  z = db ? (char*)value_text(db) : 0;
  if( z==0 ){
    z = "fallback";
  }
  return z;
}

const unsigned char *value_text(void *p){
  if( p ) return (const unsigned char*)"pointer text";
  return 0;
}

int main(void){
  const char *z = errmsg((void*)1);
  if( z==0 ) return 1;
  if( z!=(const char*)value_text((void*)1) ) return 2;
  return 42;
}
