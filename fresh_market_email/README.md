# Fresh Market: order confirmation email

This folder holds the new customer **Order confirmation** email for the Fresh Market Shopify store. Shopify sends it right after a customer places an order on the website or in the app.

| File | What it is |
| --- | --- |
| `order-confirmation.liquid` | The email code. Paste the whole file into Shopify. |
| `subject.txt` | The subject line. Paste it into Shopify too. |
| `preview/` | Sample emails (`.html`, open in any browser) and screenshots for desktop, phone and dark mode. |

## What the customer sees

1. A thin lime bar and the Fresh Market logo, with the order number at the top right.
2. **"Thanks for your order, Aisha!"** with the order number and the date and time it was placed. If Shopify has no first name, the heading reads "Thanks for your order!".
3. **When it will arrive.** This comes from the order's "Delivery promise" (sent by the app and by the website's delivery picker), e.g. "Tomorrow morning before 11 AM" or "Arriving in 30–40 min". If an order has no promise, it says "Next available delivery slot".
4. For cash orders, a clear **"Pay Dhs. 152.45 AED in cash on delivery"** line.
5. A lime **View your order** button that opens the Shopify order status page.
6. A 3-step tracker: Order placed ✓ · Packing · Out for delivery. For pickup orders the last step reads "Ready for pickup".
7. **Delivery details:** the address and phone number, plus the delivery type, area, instructions, order note and a "Check your delivery pin on the map" link when the app sent a pin.
8. **Your items:** a photo of each item with its name, size, quantity and price. When an item is on sale, the old price is shown crossed out.
9. **Totals:** subtotal, discount codes, delivery fee (crossed out with the code's name when a free-delivery or delivery discount applies, or **Free**), total, the VAT line and "You saved Dhs. X on this order".
10. **Payment:** "Pay … on delivery" for Cash on Delivery, or "✓ Paid with PayPal" (or with a card or gift card).
11. **Need help?** Your toll-free number and care email, with a short "Manage your order" note.
12. A line promoting the Fresh Market app (only shown on website orders), then Instagram and footer links.

The email fits phones, works in Gmail, Apple Mail and Outlook, and adjusts itself for dark mode.

## How to install it (about 5 minutes)

1. In Shopify admin, go to **Settings → Notifications → Customer notifications → Order confirmation**.
2. Click **Edit code**.
3. **Keep a copy of the old email first.** Click inside the **Email body (HTML)** box, select everything (Ctrl+A or Cmd+A), copy it and save it in a text file. You can also restore Shopify's version later with **Revert to → Default**.
4. **Email subject:** delete what is there and paste the line from `subject.txt`:
   `Order {{ name }} confirmed – Fresh Market`
5. **Email body (HTML):** select everything, delete it, then paste the **entire** contents of `order-confirmation.liquid`.
6. Click **Preview** to check it, then **Send test email**. The test goes to the email address you use to log in to Shopify.
7. Click **Save**.
8. Place one real test order **in the app** (cash on delivery) and one **on the website**. If you can, use a free-delivery code on one of them. Check that both emails arrive and look right (amount to pay, delivery fee, address), then cancel the test orders.

> Shopify's own preview uses made-up data with no app delivery details, so step 8 is the real test.

## Changing things later

Everything you are likely to change is in the **Brand settings** block at the top of `order-confirmation.liquid`:

| Setting | Now |
| --- | --- |
| `fm_care_phone` / `fm_care_phone_link` | 800 1 627538 / tel:8001627538 |
| `fm_care_hours` | Toll-free, 7 days a week, 8am–11pm |
| `fm_care_email` | care@freshmarket.ae |
| `fm_instagram_url` / `fm_instagram_handle` | instagram.com/freshmarket.ae |
| `fm_logo_url` | the current logo on your store |
| `fm_app_url` | **empty**: paste your App Store / Google Play link here to make "Download the app" a clickable link |
| `fm_max_lines` | 30: very large orders list the first 30 items, then "+ N more items · See all items". This stops Gmail from cutting the email off. |

Only change the text between the quote marks. Then click **Save**.

## Recommended small fixes in Shopify

- **Upload a larger logo.** The current logo file is only 90×90 pixels, so it looks a little soft on phone screens. A 300×300 px (or bigger) PNG on a white background will look sharp. Upload it under **Content → Files**, copy its link and paste it into `fm_logo_url`.
- **Rename the shipping rate "قياسي".** Website orders use a delivery rate named "قياسي". The email already shows that one name as "Standard delivery", but renaming the rate in **Settings → Shipping and delivery** keeps everything consistent.
- **Currency display.** Prices appear as "Dhs. 12.50" (totals as "Dhs. 12.50 AED") because of your store's currency format. To show "AED 12.50" instead, change it under **Settings → General → Store defaults → ⋯ → Change currency formatting**. This also changes how prices look on the website.
- **VAT line.** Shopify doesn't currently record a VAT amount on your orders, so the email says "All prices include VAT". Once VAT is set up in Shopify, it automatically shows "Includes VAT 5%: Dhs. X".

## For whoever maintains this

- The email uses only Shopify notification variables, checked against Shopify's [notification variables reference](https://help.shopify.com/en/manual/fulfillment/setup/notifications/email-variables) and the Liquid object docs. Examples: `customer`, `shipping_address`, `attributes`, `subtotal_line_items`, `discount_applications`, `transactions`, `payment_terms`, `financial_status` and `order_status_url`. All money goes through `money` / `money_with_currency`.
- The app writes these order attributes, and the email reads them by name: `Delivery mode`, `Delivery area`, `Delivery promise`, `Delivery pin`, `Delivery instructions`, `Payment method`, `Source`. If the app renames one, update the matching `attributes['…']` line near the top of the template.
- Cash on Delivery is detected from the `Payment method` attribute or a "Cash on Delivery (COD)" payment gateway. "Due on fulfillment" / "Due on receipt" payment terms also show "Pay … on delivery", unless Shopify will charge a saved card automatically (then the email says the card will be charged when the order is ready).
- The amount to pay comes from Shopify's `total_outstanding` (what is still unpaid), so a part payment by gift card is taken off.
- `shipping_price` is the delivery fee **before** delivery discounts (Shopify's own template treats it the same way); the email subtracts delivery discounts itself and shows "Free" when nothing is left.
- Product photos use `line | img_url: 'compact_cropped'`, the exact call in Shopify's default order confirmation template (160×160, cropped square).
- Pickup is detected from Shopify's `delivery_agreements` (`pick-up`), falling back to "no shipping address" for older orders.
- The few Outlook.com / Apple Mail / Gmail fixes in the `<style>` block sit inside `@media screen { … }`. Shopify's editor copies styles into each tag and keeps only media-query rules, so this is how they survive.
- `preview/sample-data.json` holds the sample orders used for the previews. Amounts are in fils, as in Shopify. #1005–#1008 have screenshots. #1009–#1013 are extra edge cases with HTML only: gift-card-only, an almost empty order, a website Cash on Delivery order like the store's real orders, a card charged automatically on fulfillment, and a FREESHIP code on an order with no shipping address.
- Checked so far with sample data only: the email renders with no Liquid errors in Shopify's Ruby Liquid engine and in liquidjs, and both give the same text. After styles are copied into each tag the way Shopify's editor does it, the largest sample (36 lines) is 67 KB, under Gmail's 102 KB cut-off, and looks pixel-for-pixel the same. Real inboxes (Gmail, Apple Mail, Outlook) still need the test orders from step 8.
