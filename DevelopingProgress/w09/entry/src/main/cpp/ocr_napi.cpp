#include "napi/native_api.h"
#include <tesseract/baseapi.h>
#include <tesseract/resultiterator.h>
#include <leptonica/allheaders.h>
#include <algorithm>
#include <cstdint>
#include <memory>
#include <string>
#include <vector>
#include <zlib.h>

namespace {
struct Span { std::string text; int x=0,y=0,w=0,h=0; float confidence=0; };
struct Line : Span { std::vector<Span> words; };
struct Job {
  napi_async_work work=nullptr; napi_deferred deferred=nullptr;
  std::vector<uint8_t> rgba; int width=0,height=0;
  std::string directory,error; std::vector<Line> lines;
};
bool ReadString(napi_env env,napi_value value,std::string& out) {
  size_t n=0;if(napi_get_value_string_utf8(env,value,nullptr,0,&n)!=napi_ok)return false;
  std::vector<char> b(n+1);if(napi_get_value_string_utf8(env,value,b.data(),b.size(),&n)!=napi_ok)return false;
  out.assign(b.data(),n);return true;
}
void Execute(napi_env,void* data) {
  auto* job=static_cast<Job*>(data);
  try {
    tesseract::TessBaseAPI api;
    api.SetVariable("debug_file","/dev/null");
    if(api.Init(job->directory.c_str(),"chi_sim+eng",tesseract::OEM_LSTM_ONLY)!=0){job->error="离线中文模型初始化失败";return;}
    api.SetVariable("preserve_interword_spaces","1");
    api.SetPageSegMode(tesseract::PSM_AUTO);
    PIX* raw=pixCreate(job->width,job->height,8);
    if(!raw){job->error="图片解码内存不足";return;}
    std::unique_ptr<PIX,void(*)(PIX*)> pix(raw,[](PIX* p){pixDestroy(&p);});
    const int stride=pixGetWpl(raw);l_uint32* pixels=pixGetData(raw);
    for(int y=0;y<job->height;++y){
      for(int x=0;x<job->width;++x){
        const size_t at=(static_cast<size_t>(y)*job->width+x)*4;
        const int a=job->rgba[at+3];
        const int gray=(77*job->rgba[at]+150*job->rgba[at+1]+29*job->rgba[at+2]+128)>>8;
        SET_DATA_BYTE(pixels+y*stride,x,(gray*a+255*(255-a)+127)/255);
      }
    }
    pixSetResolution(raw,200,200);api.SetImage(raw);
    if(api.Recognize(nullptr)!=0){job->error="离线识别未完成，请裁剪图片后重试";return;}
    std::unique_ptr<tesseract::ResultIterator> it(api.GetIterator());
    if(!it)return;
    do {
      if(it->IsAtBeginningOf(tesseract::RIL_TEXTLINE)){
        std::unique_ptr<char[]> text(it->GetUTF8Text(tesseract::RIL_TEXTLINE));
        int l=0,t=0,r=0,b=0;
        if(text && it->BoundingBox(tesseract::RIL_TEXTLINE,&l,&t,&r,&b)){
          Line line;line.text=text.get();line.x=l;line.y=t;line.w=r-l;line.h=b-t;
          line.confidence=it->Confidence(tesseract::RIL_TEXTLINE);job->lines.push_back(std::move(line));
        }
      }
      if(!job->lines.empty()){
        std::unique_ptr<char[]> text(it->GetUTF8Text(tesseract::RIL_WORD));
        int l=0,t=0,r=0,b=0;
        if(text && it->BoundingBox(tesseract::RIL_WORD,&l,&t,&r,&b)){
          Span word;word.text=text.get();word.x=l;word.y=t;word.w=r-l;word.h=b-t;
          word.confidence=it->Confidence(tesseract::RIL_WORD);job->lines.back().words.push_back(std::move(word));
        }
      }
    }while(it->Next(tesseract::RIL_WORD));
  }catch(const std::exception& e){job->error=e.what();}
  catch(...){job->error="离线识别发生异常";}
}
void StringProperty(napi_env env,napi_value object,const char* key,const std::string& s){
  napi_value v;napi_create_string_utf8(env,s.c_str(),s.size(),&v);napi_set_named_property(env,object,key,v);
}
void NumberProperty(napi_env env,napi_value object,const char* key,double n){
  napi_value v;napi_create_double(env,n,&v);napi_set_named_property(env,object,key,v);
}
napi_value MakeSpan(napi_env env,const Span& s){
  napi_value v;napi_create_object(env,&v);StringProperty(env,v,"text",s.text);
  NumberProperty(env,v,"x",s.x);NumberProperty(env,v,"y",s.y);NumberProperty(env,v,"width",s.w);NumberProperty(env,v,"height",s.h);
  NumberProperty(env,v,"confidence",s.confidence);return v;
}
void Complete(napi_env env,napi_status status,void* data){
  std::unique_ptr<Job> job(static_cast<Job*>(data));
  if(status!=napi_ok && job->error.empty())job->error="离线识别任务未完成";
  if(!job->error.empty()){
    napi_value message,error;napi_create_string_utf8(env,job->error.c_str(),NAPI_AUTO_LENGTH,&message);
    napi_create_error(env,nullptr,message,&error);napi_reject_deferred(env,job->deferred,error);
  }else{
    napi_value result;napi_create_array_with_length(env,job->lines.size(),&result);
    for(size_t i=0;i<job->lines.size();++i){
      const auto& line=job->lines[i];napi_value v=MakeSpan(env,line),words;
      napi_create_array_with_length(env,line.words.size(),&words);
      for(size_t j=0;j<line.words.size();++j)napi_set_element(env,words,j,MakeSpan(env,line.words[j]));
      napi_set_named_property(env,v,"words",words);napi_set_element(env,result,i,v);
    }
    napi_resolve_deferred(env,job->deferred,result);
  }
  napi_delete_async_work(env,job->work);
}
napi_value Recognize(napi_env env,napi_callback_info info){
  size_t argc=4;napi_value args[4];napi_get_cb_info(env,info,&argc,args,nullptr,nullptr);
  auto job=std::make_unique<Job>();void* buffer=nullptr;size_t size=0;
  if(argc!=4 || napi_get_arraybuffer_info(env,args[0],&buffer,&size)!=napi_ok ||
     napi_get_value_int32(env,args[1],&job->width)!=napi_ok || napi_get_value_int32(env,args[2],&job->height)!=napi_ok ||
     !ReadString(env,args[3],job->directory) || job->width<1 || job->height<1 ||
     static_cast<int64_t>(job->width)*job->height>12000000 ||
     size!=static_cast<size_t>(job->width)*job->height*4){
    napi_throw_type_error(env,nullptr,"无效的离线识别图片参数");return nullptr;
  }
  job->rgba.assign(static_cast<uint8_t*>(buffer),static_cast<uint8_t*>(buffer)+size);
  napi_value promise,name;napi_create_promise(env,&job->deferred,&promise);
  napi_create_string_utf8(env,"ScreenshotToTaskOfflineOCR",NAPI_AUTO_LENGTH,&name);
  const napi_status created=napi_create_async_work(env,nullptr,name,Execute,Complete,job.get(),&job->work);
  if(created!=napi_ok || napi_queue_async_work(env,job->work)!=napi_ok){
    if(job->work)napi_delete_async_work(env,job->work);
    napi_value message,error;napi_create_string_utf8(env,"无法启动离线识别任务",NAPI_AUTO_LENGTH,&message);
    napi_create_error(env,nullptr,message,&error);napi_reject_deferred(env,job->deferred,error);
    return promise;
  }
  job.release();return promise;
}
struct InflateJob {
  napi_async_work work=nullptr;napi_deferred deferred=nullptr;
  std::vector<uint8_t> data;std::string text,error;uint32_t size=0,crc=0,method=0;
};
void ExecuteInflate(napi_env,void* value){
  auto* job=static_cast<InflateJob*>(value);
  try{
    std::vector<uint8_t> output(job->size+1);
    if(job->method==0){if(job->data.size()!=job->size){job->error="Word 正文长度错误";return;}std::copy(job->data.begin(),job->data.end(),output.begin());}
    else{
      z_stream stream{};stream.next_in=job->data.data();stream.avail_in=static_cast<uInt>(job->data.size());stream.next_out=output.data();stream.avail_out=static_cast<uInt>(output.size());
      if(inflateInit2(&stream,-MAX_WBITS)!=Z_OK){job->error="无法初始化 Word 解压器";return;}
      const int result=inflate(&stream,Z_FINISH);const bool valid=result==Z_STREAM_END&&stream.total_out==job->size&&stream.total_in==job->data.size();inflateEnd(&stream);
      if(!valid){job->error="Word 正文解压超过限制或数据损坏";return;}
    }
    if(static_cast<uint32_t>(crc32(0,output.data(),job->size))!=job->crc){job->error="Word 正文校验失败";return;}
    job->text.assign(reinterpret_cast<const char*>(output.data()),job->size);
  }catch(const std::exception& e){job->error=e.what();}catch(...){job->error="Word 正文解压失败";}
}
void CompleteInflate(napi_env env,napi_status status,void* value){
  std::unique_ptr<InflateJob> job(static_cast<InflateJob*>(value));
  if(status!=napi_ok&&job->error.empty())job->error="Word 解压任务未完成";
  napi_value result;
  if(job->error.empty()){napi_create_string_utf8(env,job->text.data(),job->text.size(),&result);napi_resolve_deferred(env,job->deferred,result);}
  else{napi_value message;napi_create_string_utf8(env,job->error.c_str(),NAPI_AUTO_LENGTH,&message);napi_create_error(env,nullptr,message,&result);napi_reject_deferred(env,job->deferred,result);}
  napi_delete_async_work(env,job->work);
}
napi_value InflateWord(napi_env env,napi_callback_info info){
  size_t argc=4;napi_value args[4];napi_get_cb_info(env,info,&argc,args,nullptr,nullptr);auto job=std::make_unique<InflateJob>();void* bytes=nullptr;size_t length=0;
  if(argc!=4||napi_get_arraybuffer_info(env,args[0],&bytes,&length)!=napi_ok||length>20*1024*1024||napi_get_value_uint32(env,args[1],&job->size)!=napi_ok||job->size>4*1024*1024||napi_get_value_uint32(env,args[2],&job->crc)!=napi_ok||napi_get_value_uint32(env,args[3],&job->method)!=napi_ok||(job->method!=0&&job->method!=8)){
    napi_throw_type_error(env,nullptr,"无效的 Word 解压参数");return nullptr;
  }
  job->data.assign(static_cast<uint8_t*>(bytes),static_cast<uint8_t*>(bytes)+length);napi_value promise,name;napi_create_promise(env,&job->deferred,&promise);napi_create_string_utf8(env,"ScreenshotToTaskWord",NAPI_AUTO_LENGTH,&name);
  if(napi_create_async_work(env,nullptr,name,ExecuteInflate,CompleteInflate,job.get(),&job->work)!=napi_ok||napi_queue_async_work(env,job->work)!=napi_ok){if(job->work)napi_delete_async_work(env,job->work);napi_value message,error;napi_create_string_utf8(env,"无法启动 Word 读取任务",NAPI_AUTO_LENGTH,&message);napi_create_error(env,nullptr,message,&error);napi_reject_deferred(env,job->deferred,error);return promise;}
  job.release();return promise;
}
napi_value Init(napi_env env,napi_value exports){
  napi_property_descriptor methods[]={{"recognize",nullptr,Recognize,nullptr,nullptr,nullptr,napi_default,nullptr},{"inflateWord",nullptr,InflateWord,nullptr,nullptr,nullptr,napi_default,nullptr}};
  napi_define_properties(env,exports,2,methods);return exports;
}
napi_module module={1,0,nullptr,Init,"jtocr",nullptr,{0}};
}
extern "C" __attribute__((constructor)) void RegisterJtOcr(){napi_module_register(&module);}
