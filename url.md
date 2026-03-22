deploy lên __Vercel/Netlify__ là cách tốt nhất để có URL public ổn định (không bị đổi như tunnel).

## 1) Deploy Vercel (khuyên dùng)

__Thiết lập chuẩn cho project này:__

- Framework preset: `Vite`
- Build command: `npm run build`
- Output directory: `dist`

__Các bước:__

1. Đưa code lên GitHub (repo chứa `rv-projects-fecredit/fe-credit-ai-demo`).
2. Vào vercel.com → New Project → import repo.
3. Chọn đúng thư mục gốc project nếu là monorepo: `rv-projects-fecredit/fe-credit-ai-demo`.
4. Kiểm tra build settings như trên.
5. Deploy → nhận URL dạng `https://<app>.vercel.app`.

## 2) Deploy Netlify

__Thiết lập chuẩn:__

- Build command: `npm run build`
- Publish directory: `dist`

__Quan trọng cho SPA (React Router):__ Tạo file `public/_redirects` với nội dung:

```txt
/*    /index.html   200
```

(hoặc cấu hình rewrite tương đương trong Netlify UI)

Sau đó deploy từ GitHub hoặc drag-drop thư mục `dist`.

## 3) Khi nào chọn cái nào?

- __Vercel:__ nhanh, mượt cho frontend Vite/React, preview URL theo từng commit rất tiện.
- __Netlify:__ cũng rất ổn, mạnh ở quản trị site/forms/redirects.

## 4) Domain riêng?

- __Không bắt buộc.__ Dùng luôn domain free của nền tảng (`.vercel.app` / `.netlify.app`).
- Khi cần branding mới map custom domain sau.
