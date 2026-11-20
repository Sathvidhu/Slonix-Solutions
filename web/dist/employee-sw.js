const portal=new URL('employee.html',self.location.href);
self.addEventListener('notificationclick',event=>{
  event.notification.close();
  event.waitUntil((async()=>{
    const target=portal.href+'#notifications';
    const windows=await clients.matchAll({type:'window',includeUncontrolled:true});
    const existing=windows.find(client=>new URL(client.url).pathname===portal.pathname);
    if(existing){
      await existing.navigate(target);
      await existing.focus();
    }else await clients.openWindow(target);
  })());
});

importScripts('https://www.gstatic.com/firebasejs/10.13.2/firebase-app-compat.js',
  'https://www.gstatic.com/firebasejs/10.13.2/firebase-messaging-compat.js');
const config=JSON.parse(new URL(self.location.href).searchParams.get('config')||'{}');
firebase.initializeApp(config);
firebase.messaging().onBackgroundMessage(payload=>{
  const id=payload.data?.notification_id;
  return self.registration.showNotification('Montme',{
    body:'You have a new workspace notification.',tag:id,data:{notificationId:id}
  });
});
