// SPDX-License-Identifier: GPL-3.0-or-later
// Integration test of the installed TIP with a real Windows EDIT control.
// Sends keys only while its own test window has foreground focus.
#include <initguid.h>
#include <windows.h>
#include <msctf.h>
#include <cstdio>
#include <string>
#include <vector>

static HWND editor;
static int stage=0, result=1, focusWait=0;
static bool SendKeys(HWND window,const std::vector<INPUT>& keys) {
  if(GetForegroundWindow()!=window || GetFocus()!=editor) {
    std::puts("SKIP: test window does not have foreground focus");result=2;DestroyWindow(window);return false;
  }
  if(SendInput(static_cast<UINT>(keys.size()),const_cast<INPUT*>(keys.data()),sizeof(INPUT))!=keys.size()) {
    std::puts("FAIL: test keyboard input rejected");DestroyWindow(window);return false;
  }
  return true;
}
static void Key(std::vector<INPUT>& keys,WORD vk,bool up=false) {
  INPUT key{};key.type=INPUT_KEYBOARD;key.ki.wVk=vk;key.ki.dwFlags=up?KEYEVENTF_KEYUP:0;keys.push_back(key);
}
static LRESULT CALLBACK Window(HWND window,UINT message,WPARAM wp,LPARAM lp) {
  if(message==WM_TIMER) {
    if(stage==0) {
      if(GetForegroundWindow()!=window) {
        if(++focusWait>100){std::puts("SKIP: test window could not acquire foreground focus");result=2;DestroyWindow(window);}
        return 0;
      }
      SetFocus(editor);std::vector<INPUT> keys;Key(keys,VK_IME_ON);Key(keys,VK_IME_ON,true);SendKeys(window,keys);
    } else if(stage==1) {
      std::vector<INPUT> keys;
      for(auto c:std::wstring(L"()")) {
        SHORT key=VkKeyScanExW(c,GetKeyboardLayout(0));
        if(key==-1 || (HIBYTE(key)&~1)!=0){std::puts("SKIP: unsupported keyboard layout");result=2;DestroyWindow(window);return 0;}
        if(HIBYTE(key)&1)Key(keys,VK_SHIFT);
        Key(keys,LOBYTE(key));Key(keys,LOBYTE(key),true);
        if(HIBYTE(key)&1)Key(keys,VK_SHIFT,true);
      }
      SendKeys(window,keys);
    } else if(stage==2) {
      std::vector<INPUT> keys;Key(keys,VK_RETURN);Key(keys,VK_RETURN,true);SendKeys(window,keys);
    } else if(stage==5) {
      wchar_t text[64]{};GetWindowTextW(editor,text,64);
      DWORD start=0,end=0;SendMessageW(editor,EM_GETSEL,reinterpret_cast<WPARAM>(&start),reinterpret_cast<LPARAM>(&end));
      std::printf("EDIT: length=%zu codes=%04x,%04x selection=%lu/%lu\n",std::wcslen(text),static_cast<unsigned>(text[0]),static_cast<unsigned>(text[1]),start,end);
      result=(std::wstring(text)==L"（）" || std::wstring(text)==L"()")&&start==1&&end==1?0:1;
      std::puts(result==0?"PASS: registered native IME leaves real EDIT caret inside committed brackets":"FAIL: registered native IME real EDIT bracket caret");
      DestroyWindow(window);
    }
    ++stage;return 0;
  }
  if(message==WM_DESTROY){PostQuitMessage(0);return 0;}
  return DefWindowProcW(window,message,wp,lp);
}
int wmain() {
  wchar_t executable[32768]{};GetModuleFileNameW(nullptr,executable,32768);
  std::wstring log(executable);log.resize(log.find_last_of(L"\\/"));log+=L"\\native-edit-control-result.log";
  _wfreopen(log.c_str(),L"w",stdout);
  HRESULT hr=CoInitializeEx(nullptr,COINIT_APARTMENTTHREADED);
  if(FAILED(hr))return 2;
  ITfThreadMgr* thread=nullptr;ITfKeystrokeMgr* keys=nullptr;TfClientId client=0;
  hr=CoCreateInstance(CLSID_TF_ThreadMgr,nullptr,CLSCTX_INPROC_SERVER,IID_ITfThreadMgr,reinterpret_cast<void**>(&thread));
  if(SUCCEEDED(hr))hr=thread->Activate(&client);
  if(SUCCEEDED(hr))hr=thread->QueryInterface(IID_ITfKeystrokeMgr,reinterpret_cast<void**>(&keys));
  if(FAILED(hr)){std::printf("SKIP: TSF activation 0x%08lx\n",static_cast<unsigned long>(hr));CoUninitialize();return 2;}
  HINSTANCE module=GetModuleHandleW(nullptr);
  WNDCLASSW type{};type.hInstance=module;type.lpfnWndProc=Window;type.lpszClassName=L"MeltypeNativeRealEditTest";type.hbrBackground=reinterpret_cast<HBRUSH>(COLOR_WINDOW+1);
  RegisterClassW(&type);
  HWND window=CreateWindowExW(0,type.lpszClassName,L"Meltype native EDIT regression test",WS_OVERLAPPEDWINDOW,200,200,480,160,nullptr,nullptr,module,nullptr);
  editor=CreateWindowExW(WS_EX_CLIENTEDGE,L"EDIT",L"",WS_CHILD|WS_VISIBLE|WS_TABSTOP|ES_AUTOHSCROLL,20,30,410,36,window,nullptr,module,nullptr);
  ShowWindow(window,SW_SHOWNORMAL);ShowWindow(window,SW_SHOWNORMAL);SetForegroundWindow(window);SetFocus(editor);
  CLSID clsid;GUID profile;CLSIDFromString(L"{F2D11628-2679-4DCC-9327-657EF2C1A450}",&clsid);CLSIDFromString(L"{825C8537-9FC0-4951-A197-1C33F77B9243}",&profile);
  ITfInputProcessorProfileMgr* profiles=nullptr;
  hr=CoCreateInstance(CLSID_TF_InputProcessorProfiles,nullptr,CLSCTX_INPROC_SERVER,IID_ITfInputProcessorProfileMgr,reinterpret_cast<void**>(&profiles));
  if(SUCCEEDED(hr)){hr=profiles->ActivateProfile(TF_PROFILETYPE_INPUTPROCESSOR,0x0411,clsid,profile,nullptr,0);profiles->Release();}
  std::printf("Activate test-thread native profile: 0x%08lx\n",static_cast<unsigned long>(hr));
  if(FAILED(hr)){DestroyWindow(window);result=2;}else SetTimer(window,1,150,nullptr);
  MSG message{};
  while(GetMessageW(&message,nullptr,0,0)>0) {
    BOOL eaten=FALSE;
    if(message.message==WM_KEYDOWN || message.message==WM_SYSKEYDOWN) {
      if(SUCCEEDED(keys->TestKeyDown(message.wParam,message.lParam,&eaten))&&eaten)keys->KeyDown(message.wParam,message.lParam,&eaten);
    } else if(message.message==WM_KEYUP || message.message==WM_SYSKEYUP) {
      if(SUCCEEDED(keys->TestKeyUp(message.wParam,message.lParam,&eaten))&&eaten)keys->KeyUp(message.wParam,message.lParam,&eaten);
    }
    if(!eaten){TranslateMessage(&message);DispatchMessageW(&message);}
  }
  keys->Release();thread->Deactivate();thread->Release();CoUninitialize();return result;
}
