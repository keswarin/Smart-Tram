const functions = require("firebase-functions");
const admin = require("firebase-admin");
const nodemailer = require("nodemailer");

admin.initializeApp();
const db = admin.firestore();

// ✅ ตั้งค่า Gmail SMTP (ใช้ App Password)
const transporter = nodemailer.createTransport({
  service: "gmail",
  auth: {
    user: "keswarin.th@gmail.com",      // 👉 ใส่อีเมลหลัก
    pass: "lamh mvdz bahd ejpe",         // 👉 ใส่ App Password (16 ตัวอักษร)
  },
});

// ✅ ส่ง OTP ไปอีเมล
exports.sendOtpEmail = functions.https.onCall(async (data, context) => {
  const { email } = data;
  if (!email) throw new functions.https.HttpsError("invalid-argument", "ต้องการ email");

  // สร้าง OTP
  const otp = Math.floor(100000 + Math.random() * 900000).toString();
  const expiresAt = Date.now() + 5 * 60 * 1000; // 5 นาที

  // บันทึก Firestore (ยังไม่สร้าง account)
  await db.collection("pending_otps").doc(email).set({
    otp,
    expiresAt,
  });

  const mailOptions = {
    from: '"Smart Tram System" <keswarin.th@gmail.com>',
    to: email,
    subject: "🔑 รหัส OTP สำหรับยืนยันบัญชี",
    html: `
      <h2>รหัส OTP สำหรับ Smart Tram</h2>
      <p>รหัสของคุณคือ:</p>
      <h1 style="color:blue">${otp}</h1>
      <p>รหัสมีอายุ 5 นาทีเท่านั้น</p>
    `,
  };

  await transporter.sendMail(mailOptions);
  return { success: true };
});
