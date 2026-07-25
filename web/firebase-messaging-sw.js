// Handles background/closed-tab push messages for the PWA (KAN-156).
// firebase_messaging (web) auto-registers this file at the site root.
importScripts(
  'https://www.gstatic.com/firebasejs/10.12.2/firebase-app-compat.js',
);
importScripts(
  'https://www.gstatic.com/firebasejs/10.12.2/firebase-messaging-compat.js',
);

// Public web app config (same values as lib/firebase_options.dart; the web
// API key is not a secret — access is governed by Firestore rules).
firebase.initializeApp({
  apiKey: 'AIzaSyA1FB4x_ljscaN66j7Jppg8MmjwwPCvHdI',
  appId: '1:517216328748:web:72bd09ba90cab9ca754589',
  messagingSenderId: '517216328748',
  projectId: 'baby-6f5b0',
  authDomain: 'baby-6f5b0.firebaseapp.com',
  storageBucket: 'baby-6f5b0.firebasestorage.app',
});

const messaging = firebase.messaging();

messaging.onBackgroundMessage((payload) => {
  const notification = payload.notification || {};
  self.registration.showNotification(notification.title || 'Baby App', {
    body: notification.body || '',
    icon: '/icons/Icon-192.png',
    badge: '/icons/Icon-192.png',
  });
});
