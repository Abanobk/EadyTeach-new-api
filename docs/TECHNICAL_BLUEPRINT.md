# EasyTech — Technical Blueprint (هيكل التطبيق والتقرير التقني الشامل)

---

## 1. App Architecture — تقسيم الأدوار (User Roles)

### 1.1 الأدوار المعرّفة
| الدور | الاسم في الكود | الوصف | شرط الدخول |
|-------|----------------|--------|-------------|
| **عميل** | `user` / Client | تصفح المنتجات، طلب خدمات، متابعة طلبات وعروض أسعار ومهامه | أي مستخدم مسجّل |
| **فني** | `technician` | عرض المهام المعيّنة له، تحديث التقدم والموقع، العهدة والمصاريف | `role == 'technician'` أو تعيين من المسؤول |
| **مسؤول / مدير** | `admin` / `staff` / `supervisor` | لوحة تحكم كاملة: طلبات، عملاء، منتجات، مهام، عروض أسعار، حسابات، CRM، إشعارات، صلاحيات | `canAccessAdmin` (admin, staff, supervisor أو قائمة إيميلات إضافية) |

### 1.2 نقطة الدخول وتوجيه الأدوار
- **Splash** → إن وجدت جلسة: **Role Select**؛ وإلا: **Login**.
- **Role Select** يعرض:
  - **عميل**: يفتح `/client` (ClientHomeScreen).
  - **فني**: يفتح `/technician` (TechnicianHomeScreen).
  - **مسؤول**: يظهر فقط إن `auth.canAccessAdmin`، ويفتح `/admin` (AdminHomeScreen).
- التوجيه المركزي في `main.dart`: routes مثل `/splash`, `/login`, `/role-select`, `/client`, `/technician`, `/task-detail`, `/quotation-detail`, `/admin`.

### 1.3 الصلاحيات (Permissions)
- مديرونة من الـ Backend عبر `permissions.getUserPermissions` ومخزنة في `UserModel.permissions`.
- كل عنصر في قائمة المسؤول (Drawer + Dashboard) مربوط بـ `auth.hasPermission('module.view')` (مثل `orders.view`, `tasks.view`, `accounting.view`, `permissions.view`).
- الـ Admin يستطيع كل شيء؛ غيره حسب الصلاحيات المربوطة بدوره.

---

## 2. Screen Flow — الشاشات حسب الدور

### 2.1 شاشات مشتركة (قبل اختيار الدور)
| الشاشة | الملف | الوظيفة |
|--------|-------|---------|
| Splash | `main.dart` → SplashScreen | فحص الجلسة وتوجيه لـ Role Select أو Login |
| Login | `auth/login_screen.dart` | تسجيل دخول (إيميل/كلمة مرور أو Google) |
| Role Select | `auth/role_select_screen.dart` | اختيار الدخول كـ عميل / فني / مسؤول |

### 2.2 عميل (Client)
| # | الشاشة | الملف | ملاحظات |
|---|--------|-------|----------|
| 1 | المتجر (الرئيسية) | `client/client_home_screen.dart` | بانر، فئات، منتجات مميزة، بحث، فلتر حسب فئة |
| 2 | تفاصيل المنتج | `client/product_detail_screen.dart` | عرض منتج، إضافة للسلة |
| 3 | طلب خدمة | `client/service_request_screen.dart` | نموذج طلب خدمة |
| 4 | مهامي | `client/my_tasks_screen.dart` | قائمة مهام العميل + استبيانات (Smart Survey) |
| 5 | السلة | `client/cart_screen.dart` | عناصر السلة، إتمام طلب |
| 6 | طلباتي | `client/orders_screen.dart` | قائمة الطلبات السابقة |
| 7 | عروض الأسعار | `client/client_quotations_screen.dart` | قائمة العروض + تفاصيل عرض (ClientQuotationDetailScreen) |
| 8 | بياناتي | `client/profile_screen.dart` | الملف الشخصي للعميل |

التنقل: **BottomNavigationBar** ثابت (المتجر، طلب خدمة، مهامي، السلة، طلباتي، عروض الأسعار، بياناتي).

### 2.3 فني (Technician)
| # | الشاشة | الملف | ملاحظات |
|---|--------|-------|----------|
| 1 | مهامي (الرئيسية) | `technician/technician_home_screen.dart` | قائمة مهام الفني، فلاتر (حالية، اليوم، متأخرة، منفذة)، بانر عهدة/مصاريف، إشعارات |
| 2 | تفاصيل المهمة | `technician/task_detail_screen.dart` | بيانات المهمة، بنود المهمة مع تقدم وملاحظات، ملاحظات، GPS، صور، تحصيل |
| 3 | عهدتي والمصاريف | `technician/technician_custody_screen.dart` | ملخص العهدة، تسجيل مصروف، رفع صورة إيصال |

التنقل: من الشريط العلوي (رجوع، إشعارات، عهدة، Smart Survey) وبدون BottomNavigationBar؛ القائمة الرئيسية هي قائمة المهام.

### 2.4 مسؤول / مدير (Admin)
**الشريط السفلي (BottomNavigationBar) — 5 تبويبات:**
| Index | التبويب | الشاشة | الملف |
|-------|---------|--------|-------|
| 0 | الرئيسية | لوحة التحكم | `admin_home_screen.dart` → _buildDashboard |
| 1 | الطلبات | إدارة الطلبات | `admin_orders_screen.dart` |
| 2 | العملاء | إدارة العملاء | `admin_customers_screen.dart` |
| 3 | المنتجات | إدارة المنتجات | `admin_products_screen.dart` |
| 4 | المهام | إدارة المهام | `admin_tasks_screen.dart` |

**القائمة الجانبية (Drawer) — أنظمة متقدمة (حسب الصلاحيات):**
| الشاشة | الملف | صلاحية |
|--------|-------|--------|
| عروض الأسعار | `admin_quotations_screen.dart` + `quotation_detail_screen.dart` + `create_quotation_screen.dart` | `quotations.view` |
| التصنيفات | `admin_categories_screen.dart` | `categories.view` |
| الحسابات والعهد | `admin_accounting_screen.dart` | `accounting.view` |
| نظام CRM | `admin_crm_screen.dart` + `crm_lead_detail_screen.dart` | `crm.view` |
| صندوق الرسائل | `admin_inbox_screen.dart` | `inbox.view` |
| الإشعارات | `admin_notifications_screen.dart` | `notifications.view` |
| السكرتارية | `admin_secretary_screen.dart` | `secretary.view` |
| التقارير | `admin_reports_screen.dart` | `reports.view` |
| Smart Survey (المعاينة الذكية) | `survey_entry_screen.dart` (موديول) | `surveys.view` |
| الصلاحيات | `admin_permissions_screen.dart` | `permissions.view` |

**موديول الاستبيانات (Survey):**
- `survey_entry_screen.dart` — نقطة الدخول
- `saved_surveys_screen.dart`, `survey_detail_screen.dart`, `survey_wizard_screen.dart`, `survey_edit_screen.dart`

---

## 3. Data Structure — البيانات الأساسية لكل سياق

### 3.1 المتجر (عميل)
- **Products**: `id`, `name`, `nameAr`, `price`, `imageUrl`, `categoryId` / `categoryIds`, `isFeatured`, `description` — مصدر: `products.list`.
- **Categories**: `id`, `name`, `nameAr` — مصدر: `categories.list`.
- **Store Settings**: `companyName`, `companyNameAr`, `bannerTitle`, `bannerTitleAr`, `bannerImageUrl`, `showBanner`, `showCategories` — مصدر: `storeSettings.get`.
- **Cart**: محلي عبر `CartProvider` (عناصر منتجات + كمية).

### 3.2 الطلبات (Orders)
- **Order**: `id`, `items` (قائمة)، `total`, `status`, `shippingAddress`, `notes`, `createdAt` — في العميل: `orders.getMyOrders`؛ في المسؤول: قائمة طلبات مع بيانات إضافية من الـ API.

### 3.3 المهام (Tasks)
- **Task**: `id`, `title`, `status` (pending, assigned, in_progress, completed, cancelled), `customerId`, `customerName`, `customerPhone`, `customerAddress`, `customerLocation`, `technicianId`, `technicianName` / `technician`, `scheduledAt`, `estimatedArrivalAt`, `amount`, `collectionType`, `notes`, `items` (بنود)، تقدم عام وبنود (progress، progressNote، isCompleted).
- **Task Item**: `id`, `description`, `isCompleted`, `progress`, `progressNote`, `mediaUrls`, `mediaTypes`.
- **Task Note**: `id`, `content`, `author`, `createdAt`, `mediaUrls`, `isVisibleToClient`.
- مصدر المسؤول: `tasks.list`؛ الفني: `tasks.getMyTasks` أو فلترة `tasks.list`؛ العميل: في "مهامي".

### 3.4 عروض الأسعار (Quotations)
- **Quotation**: `id`, `refNumber`, `clientUserId`, `clientName`, `clientEmail`, `clientPhone`, `items` (بنود مع quantity, unitPrice, totalPrice), `subtotal`, `status`, `pdfUrl`, `sentAt`, `clientNote`.
- المسؤول: إنشاء/تعديل/حذف/إرسال؛ العميل: عرض والرد (قبول/رفض).

### 3.5 العملاء والمستخدمين
- **User/Customer**: `id`, `name`, `email`, `phone`, `role`, `address`, `isActive`, إلخ — من `clients.list`, `clients.staff`؛ الصلاحيات من `permissions.getUserPermissions` وربط الأدوار من `permissions.assignRole`.

### 3.6 الحسابات والعهد (Accounting)
- **Dashboard**: `totalCollections`, `totalExpenses`, `totalAdvances`, `totalSettlements` — بطاقات ملخص.
- **Transaction**: `id`, `type` (custody, expense, collection, settlement), `technicianId`, `taskId`, `amount`, `description`, `receiptUrl`, `category`, `status` (pending, approved, rejected), `approvedBy`, `createdAt`.
- **Expense categories**: قائمة من الـ Backend.

### 3.7 CRM
- **Lead**: `id`, `name`, `phone`, `email`, `stage`, `value`, `assignedTo`, `activities`, إلخ.
- **Pipeline**: مراحل (مثل: جديد، اتصال، عرض، تفاوض، ربح/خسارة).

### 3.8 الإشعارات
- **Notification**: `id`, `title`, `body`, `type`, `refId`, `refType`, `data`, `isRead`, `createdAt` — قائمة من `notifications.list`؛ عداد غير مقروء من `notifications.getUnreadCount`.

### 3.9 لوحة تحكم المسؤول (Dashboard)
- **Stats**: `totalOrders`, `totalCustomers`, `totalProducts`, `totalTasks` — من `admin.getDashboardStats`.
- عرض: بطاقات إحصاء (_StatCard) + شبكة أنظمة (_SystemCard) حسب الصلاحيات.

---

## 4. Current UI Logic — الـ Widgets الأساسية للقوائم والجداول

### 4.1 الثيم والألوان (app_theme.dart)
- **AppColors**: `bg`, `card`, `border`, `text`, `muted`, `primary`, `primaryDark`, `success`, `error`, `warning`.
- **AppTheme.darkTheme**: خلفية داكنة، AppBar، ElevatedButton، حقول إدخال، BottomNavigationBar، نصوص.

### 4.2 أنماط العرض الشائعة
- **قوائم عمودية**: `ListView.builder` مع `itemBuilder` يرجع عنصراً لكل عنصر (Card أو Tile).
- **شبكات**: `GridView.builder` أو `GridView.count` لعرض بطاقات (منتجات، تصنيفات، إحصائيات، أنظمة).
- **بطاقة واحدة**: `Card` أو `Container` مع `BoxDecoration` (لون خلفية، حدود، border radius).

### 4.3 مكوّنات مخصصة متكررة
| الوظيفة | الاستخدام | مثال الملف |
|---------|-----------|------------|
| بطاقة دور (عميل/فني/مسؤول) | _RoleCard | role_select_screen.dart |
| بطاقة منتج | _ProductCard | client_home_screen.dart |
| بطاقة فئة | _CategoryCard | client_home_screen.dart |
| بطاقة طلب | _OrderCard, _AdminOrderCard | orders_screen, admin_orders_screen |
| بطاقة مهمة | _TaskCard | technician_home_screen, my_tasks_screen, admin_tasks_screen |
| بطاقة إحصاء | _StatCard, _dashCard, _statCard | admin_home_screen, admin_reports_screen, admin_accounting_screen, admin_crm_screen |
| بطاقة نظام (داشبورد) | _SystemCard | admin_home_screen |
| بطاقة مستخدم/دور | _UserCard, _buildRoleCard | admin_permissions_screen |
| بطاقة ملخص مالية | _summaryCard | technician_custody_screen |
| قسم داخل شاشة (عنوان + محتوى) | _sectionCard | task_detail_screen |
| قائمة ملاحظات | _NoteCard | my_tasks_screen |

### 4.4 أنماط تفاعل
- **فلترة**: شرائح أفقية (Chips) أو قائمة منسدلة لاختيار (مهام: حالية/اليوم/متأخرة/منفذة؛ منتجات: بحث + فئة).
- **تحديث البيانات**: `RefreshIndicator` أو زر تحديث يستدعي `setState` بعد إعادة جلب من الـ API.
- **التفاصيل**: `Navigator.push` إلى شاشة تفاصيل (مهمة، عرض سعر، منتج، عميل، ليد CRM).
- **نمط عرض المنتجات (مسؤول)**: التبديل بين Grid و List (`_isGridView`) مع `GridView.builder` و `ListView.builder`.

### 4.5 التنقل والروابط
- **عميل**: BottomNavigationBar (7 عناصر) → تعيين `_selectedIndex` وعرض `screens[_selectedIndex]`.
- **مسؤول**: BottomNavigationBar (5 عناصر) للرئيسية + Drawer للأنظمة المتقدمة؛ الدخول لشاشة جديدة عبر `Navigator.push` مع `MaterialPageRoute` و `Directionality(textDirection: TextDirection.rtl, child: Screen())`.
- **فني**: شاشة واحدة رئيسية (قائمة مهام) + انتقال لـ TaskDetail و TechnicianCustody و AdminNotifications و Survey.

### 4.6 الـ API
- Base: `ApiService.baseUrl` / `ApiService.trpcUrl` — طلبات tRPC (query/mutate) مع إرسال الجلسة (Cookie/Authorization).
- أمثلة إجراءات: `products.list`, `categories.list`, `storeSettings.get`, `tasks.list`, `tasks.getMyTasks`, `orders.getMyOrders`, `notifications.list`, `notifications.getUnreadCount`, `admin.getDashboardStats`, `clients.list`, `clients.staff`, إلخ.

---

هذا المستند يلخّص الهيكل الحالي للـ App Architecture، Screen Flow، Data Structure، و Current UI Logic لاستخدامه كأساس لإعادة بناء الهوية البصرية (UI/UX) حسب وظيفة كل شاشة.
