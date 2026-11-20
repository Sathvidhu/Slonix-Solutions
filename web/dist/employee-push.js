const sdk='https://www.gstatic.com/firebasejs/10.13.2/';
const tokenKey=user=>'montme.employee.push.'+user;

export function webPushEnabled(repo){
  return typeof Notification!=='undefined'&&Notification.permission==='granted'&&
    Boolean(repo.session?.user?.id&&localStorage.getItem(tokenKey(repo.session.user.id)));
}

export async function enableWebPush(repo,settings,onMessage){
  const config=settings?.web;
  const vapidKey=settings?.web_vapid_key;
  if(!config?.apiKey||!config.appId||!config.projectId||!config.messagingSenderId||!vapidKey){
    throw Error('Browser push has not been configured. Contact your company admin.');
  }
  if(!('serviceWorker' in navigator)||!('Notification' in window))throw Error('This browser does not support push notifications.');
  if(await Notification.requestPermission()!=='granted')throw Error('Allow notifications in your browser to enable alerts.');
  const [{initializeApp,getApps},{getMessaging,getToken,isSupported,onMessage:subscribe}]=await Promise.all([
    import(sdk+'firebase-app.js'),import(sdk+'firebase-messaging.js')
  ]);
  if(!await isSupported())throw Error('This browser does not support Firebase push notifications.');
  const app=getApps().find(app=>app.name==='montme-employee')||initializeApp(config,'montme-employee');
  const worker=new URL('employee-sw.js',location.href);
  worker.searchParams.set('config',JSON.stringify(config));
  const registration=await navigator.serviceWorker.register(worker,{scope:'./employee.html'});
  if(!registration.active){
    const pending=registration.installing||registration.waiting;
    if(!pending)throw Error('Browser notification worker is unavailable.');
    await new Promise((resolve,reject)=>{
      const check=()=>{
        if(pending.state==='activated')resolve();
        if(pending.state==='redundant')reject(Error('Browser notification worker failed to start.'));
      };
      pending.addEventListener('statechange',check);
      check();
    });
  }
  const messaging=getMessaging(app);
  const token=await getToken(messaging,{vapidKey,serviceWorkerRegistration:registration});
  if(!token)throw Error('Unable to register this browser for push notifications.');
  const key=tokenKey(repo.session.user.id),old=localStorage.getItem(key);
  await repo.request('/rest/v1/rpc/register_web_push',{method:'POST',body:{token_input:token}});
  if(old&&old!==token)await unregister(repo,old);
  localStorage.setItem(key,token);
  enableWebPush.unsubscribe?.();
  enableWebPush.unsubscribe=subscribe(messaging,payload=>{
    const id=payload.data?.notification_id;
    registration.showNotification('Montme',{body:'You have a new workspace notification.',icon:new URL('montme-mark.png',location.href).href,tag:id,data:{notificationId:id}}).catch(()=>{});
    onMessage?.();
  });
}
function unregister(repo,token){
  return repo.request('/rest/v1/rpc/unregister_push_device',{method:'POST',body:{token_input:token}});
}
export async function disableWebPush(repo){
  if(!repo.session?.user?.id)return;
  const key=tokenKey(repo.session.user.id),token=localStorage.getItem(key);
  if(token){
    const registration=await navigator.serviceWorker?.getRegistration(location.href);
    const subscription=await registration?.pushManager.getSubscription();
    await subscription?.unsubscribe();
    await unregister(repo,token);
  }
  localStorage.removeItem(key);
  enableWebPush.unsubscribe?.();
  enableWebPush.unsubscribe=null;
}
