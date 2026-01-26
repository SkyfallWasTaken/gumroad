import { useForm } from "@inertiajs/react";
import { DirectUpload } from "@rails/activestorage";
import { isEqual } from "lodash-es";
import * as React from "react";

import { buildProductPayload, filterFilesInContent } from "$app/data/product_edit";
import { OtherRefundPolicy } from "$app/data/products/other_refund_policies";
import { Thumbnail } from "$app/data/thumbnails";
import { usePersistentExternalScript } from "$app/hooks/usePersistentExternalScript";
import { RatingsWithPercentages } from "$app/parsers/product";
import { CurrencyCode } from "$app/utils/currency";
import { Taxonomy } from "$app/utils/discover";
import { ALLOWED_EXTENSIONS } from "$app/utils/file";
import { assertResponseError, request } from "$app/utils/request";
import { cast } from "ts-safe-cast";

import { Seller } from "$app/components/Product";
import { getDownloadUrl } from "$app/components/ProductEdit/ContentTab/FileEmbed";
import { Page } from "$app/components/ProductEdit/ContentTab/PageTab";
import { type TabName, getUpdateUrlForTab } from "$app/components/ProductEdit/Layout";
import { RefundPolicy } from "$app/components/ProductEdit/RefundPolicy";
import {
  ProductEditContext,
  Product,
  ProfileSection,
  ExistingFileEntry,
  ShippingCountry,
  ContentUpdates,
} from "$app/components/ProductEdit/state";
import { ImageUploadSettingsContext } from "$app/components/RichTextEditor";
import { showAlert } from "$app/components/server-components/Alert";

export type FullEditProps = {
  product: Product;
  id: string;
  unique_permalink: string;
  thumbnail: Thumbnail | null;
  currency_type: CurrencyCode;
  is_tiered_membership: boolean;
  is_physical: boolean;
  successful_sales_count: number;
  seller: Seller;
  s3_url: string;
  aws_key: string;
  dropbox_picker_api_key: string;
  active_tab: TabName;
  errors?: Record<string, string>;
  refund_policies: OtherRefundPolicy[];
  is_listed_on_discover: boolean;
  profile_sections: ProfileSection[];
  taxonomies: Taxonomy[];
  earliest_membership_price_change_date: string;
  custom_domain_verification_status: { success: boolean; message: string } | null;
  sales_count_for_inventory: number;
  ratings: RatingsWithPercentages;
  available_countries: ShippingCountry[];
  google_client_id: string;
  google_calendar_enabled: boolean;
  seller_refund_policy_enabled: boolean;
  seller_refund_policy: Pick<RefundPolicy, "title" | "fine_print">;
  cancellation_discounts_enabled: boolean;
  ai_generated: boolean;
  existing_files: ExistingFileEntry[];
};

const pagesHaveSameContent = (pages1: Page[], pages2: Page[]): boolean => isEqual(pages1, pages2);

const findUpdatedContent = (product: Product, lastSavedProduct: Product) => {
  const contentUpdatedVariantIds = product.variants
    .filter((variant) => {
      const lastSavedVariant = lastSavedProduct.variants.find((v) => v.id === variant.id);
      return !pagesHaveSameContent(variant.rich_content, lastSavedVariant?.rich_content ?? []);
    })
    .map((variant) => variant.id);

  const sharedContentUpdated = !pagesHaveSameContent(product.rich_content, lastSavedProduct.rich_content);

  return {
    sharedContentUpdated,
    contentUpdatedVariantIds,
  };
};

type ProductEditProviderProps = {
  props: FullEditProps;
  children: React.ReactNode;
};

export function ProductEditProvider({ props, children }: ProductEditProviderProps) {
  const [product, setProduct] = React.useState(props.product);
  const [contentUpdates, setContentUpdates] = React.useState<ContentUpdates>(null);
  const [currencyType, setCurrencyType] = React.useState<CurrencyCode>(props.currency_type);
  const lastSavedProductRef = React.useRef<Product>(structuredClone(props.product));

  const updateProduct = (update: Partial<Product> | ((product: Product) => void)) =>
    setProduct((prevProduct) => {
      const updated = { ...prevProduct };
      if (typeof update === "function") update(updated);
      else Object.assign(updated, update);
      return updated;
    });

  const [existingFiles, setExistingFiles] = React.useState<ExistingFileEntry[]>(props.existing_files);
  const [imagesUploading, setImagesUploading] = React.useState<Set<File>>(new Set());

  const form = useForm({});

  const save = () => {
    const filteredProduct = filterFilesInContent(props.id, product);
    const payload = buildProductPayload(filteredProduct, currencyType);

    return new Promise<void>((resolve, reject) => {
      form.transform(() => payload);
      form.patch(getUpdateUrlForTab(props.active_tab, props.unique_permalink), {
        preserveScroll: true,
        onSuccess: () => {
          const { contentUpdatedVariantIds, sharedContentUpdated } = findUpdatedContent(
            product,
            lastSavedProductRef.current,
          );
          const contentUpdated = sharedContentUpdated || contentUpdatedVariantIds.length > 0;

          if (props.successful_sales_count > 0 && contentUpdated) {
            const uniquePermalinkOrVariantIds = product.has_same_rich_content_for_all_variants
              ? [props.unique_permalink]
              : contentUpdatedVariantIds;

            setContentUpdates({
              uniquePermalinkOrVariantIds,
            });
          }
          lastSavedProductRef.current = structuredClone(product);
          resolve();
        },
        onError: (errors) => {
          const errorMessage = Object.values(errors)[0];
          if (errorMessage) showAlert(errorMessage, "error");
          reject(new Error(errorMessage ?? "Save failed"));
        },
      });
    });
  };

  const contextValue = React.useMemo(
    () => ({
      id: props.id,
      product,
      updateProduct,
      uniquePermalink: props.unique_permalink,
      thumbnail: props.thumbnail,
      refundPolicies: props.refund_policies,
      currencyType,
      setCurrencyType,
      isListedOnDiscover: props.is_listed_on_discover,
      isPhysical: props.is_physical,
      isTieredMembership: props.is_tiered_membership,
      profileSections: props.profile_sections,
      taxonomies: props.taxonomies,
      earliestMembershipPriceChangeDate: new Date(props.earliest_membership_price_change_date),
      customDomainVerificationStatus: props.custom_domain_verification_status,
      salesCountForInventory: props.sales_count_for_inventory,
      successfulSalesCount: props.successful_sales_count,
      ratings: props.ratings,
      seller: props.seller,
      existingFiles,
      setExistingFiles,
      awsKey: props.aws_key,
      s3Url: props.s3_url,
      availableCountries: props.available_countries,
      saving: form.processing,
      save,
      googleClientId: props.google_client_id,
      googleCalendarEnabled: props.google_calendar_enabled,
      seller_refund_policy_enabled: props.seller_refund_policy_enabled,
      seller_refund_policy: props.seller_refund_policy,
      cancellationDiscountsEnabled: props.cancellation_discounts_enabled,
      contentUpdates,
      setContentUpdates,
      filesById: new Map(product.files.map((file) => [file.id, { ...file, url: getDownloadUrl(props.id, file) }])),
      aiGenerated: props.ai_generated,
      activeTab: props.active_tab,
      setActiveTab: () => {},
    }),
    [props, product, currencyType, existingFiles, form.processing, contentUpdates],
  );

  const imageSettings = React.useMemo(
    () => ({
      isUploading: imagesUploading.size > 0,
      onUpload: (file: File) => {
        setImagesUploading((prev) => new Set(prev).add(file));
        return new Promise<string>((resolve, reject) => {
          const upload = new DirectUpload(file, Routes.rails_direct_uploads_path());
          upload.create((error, blob) => {
            setImagesUploading((prev) => {
              const updated = new Set(prev);
              updated.delete(file);
              return updated;
            });

            if (error) reject(error);
            else
              request({
                method: "GET",
                accept: "json",
                url: Routes.s3_utility_cdn_url_for_blob_path({ key: blob.key }),
              })
                .then((response) => response.json())
                .then((data) => resolve(cast<{ url: string }>(data).url))
                .catch((e: unknown) => {
                  assertResponseError(e);
                  reject(e);
                });
          });
        });
      },
      allowedExtensions: ALLOWED_EXTENSIONS,
    }),
    [imagesUploading.size],
  );

  usePersistentExternalScript(
    `https://www.dropbox.com/static/api/2/dropins.js?app_key=${props.dropbox_picker_api_key}`,
  );

  return (
    <ProductEditContext.Provider value={contextValue}>
      <ImageUploadSettingsContext.Provider value={imageSettings}>
        {children}
      </ImageUploadSettingsContext.Provider>
    </ProductEditContext.Provider>
  );
}
