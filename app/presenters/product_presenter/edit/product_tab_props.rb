# frozen_string_literal: true

class ProductPresenter::Edit::ProductTabProps
  include Rails.application.routes.url_helpers
  include PreorderHelper

  attr_reader :product, :pundit_user, :ai_generated

  def initialize(product:, pundit_user:, ai_generated: false)
    @product = product
    @pundit_user = pundit_user
    @ai_generated = ai_generated
  end

  def props
    refund_policy = product.find_or_initialize_product_refund_policy
    profile_sections = product.user.seller_profile_products_sections
    collaborator = product.collaborator_for_display
    cancellation_discount = product.cancellation_discount_offer_code

    {
      thumbnail: product.thumbnail&.alive&.as_json,
      refund_policies: product.user
        .product_refund_policies
        .for_visible_and_not_archived_products
        .where.not(product_id: product.id)
        .order(updated_at: :desc)
        .select("refund_policies.*", "links.name")
        .as_json,
      earliest_membership_price_change_date: BaseVariant::MINIMUM_DAYS_TIL_EXISTING_MEMBERSHIP_PRICE_CHANGE.days.from_now.in_time_zone(product.user.timezone).iso8601,
      custom_domain_verification_status: custom_domain_verification_status,
      sales_count_for_inventory: product.max_purchase_count? ? product.sales_count_for_inventory : 0,
      ratings: product.rating_stats,
      available_countries: ShippingDestination::Destinations.shipping_countries.map { { code: _1[0], name: _1[1] } },
      google_client_id: GlobalConfig.get("GOOGLE_CLIENT_ID"),
      google_calendar_enabled: Feature.active?(:google_calendar_link, product.user),
      seller_refund_policy_enabled: product.user.account_level_refund_policy_enabled?,
      seller_refund_policy: {
        title: product.user.refund_policy.title,
        fine_print: product.user.refund_policy.fine_print,
      },
      cancellation_discounts_enabled: Feature.active?(:cancellation_discounts, product.user),
      ai_generated:,
      product: product_props(refund_policy, profile_sections, collaborator, cancellation_discount),
    }
  end

  private
    def product_props(refund_policy, profile_sections, collaborator, cancellation_discount)
      {
        description: product.description || "",
        price_cents: product.price_cents,
        customizable_price: !!product.customizable_price,
        suggested_price_cents: product.suggested_price_cents,
        **ProductPresenter::InstallmentPlanProps.new(product:).props,
        custom_button_text_option: product.custom_button_text_option.presence,
        custom_summary: product.custom_summary,
        custom_attributes: product.custom_attributes,
        file_attributes: product.file_info_for_product_page.map { { name: _1.to_s, value: _2 } },
        max_purchase_count: product.max_purchase_count,
        quantity_enabled: product.quantity_enabled,
        can_enable_quantity: product.can_enable_quantity?,
        should_show_sales_count: product.should_show_sales_count,
        hide_sold_out_variants: product.hide_sold_out_variants?,
        is_epublication: product.is_epublication?,
        product_refund_policy_enabled: product.product_refund_policy_enabled?,
        refund_policy: {
          allowed_refund_periods_in_days: RefundPolicy::ALLOWED_REFUND_PERIODS_IN_DAYS.keys.map do
            {
              key: _1,
              value: RefundPolicy::ALLOWED_REFUND_PERIODS_IN_DAYS[_1]
            }
          end,
          max_refund_period_in_days: refund_policy.max_refund_period_in_days,
          fine_print: refund_policy.fine_print,
          fine_print_enabled: refund_policy.fine_print.present?,
          title: refund_policy.title,
        },
        covers: product.display_asset_previews.as_json,
        require_shipping: product.require_shipping?,
        integrations: Integration::ALL_NAMES.index_with { |name| product.find_integration_by_name(name).as_json },
        variants: variants_props,
        availabilities: availabilities_props,
        shipping_destinations: product.shipping_destinations.alive.map do |shipping_destination|
          {
            country_code: shipping_destination.country_code,
            one_item_rate_cents: shipping_destination.one_item_rate_cents,
            multiple_items_rate_cents: shipping_destination.multiple_items_rate_cents,
          }
        end,
        section_ids: profile_sections.filter_map { |section| section.external_id if section.shown_products.include?(product.id) },
        taxonomy_id: product.taxonomy_id&.to_s,
        tags: product.tags.pluck(:name),
        display_product_reviews: product.display_product_reviews,
        is_adult: product.is_adult,
        discover_fee_per_thousand: product.discover_fee_per_thousand,
        custom_domain: product.custom_domain&.domain || "",
        free_trial_enabled: product.free_trial_enabled,
        free_trial_duration_amount: product.free_trial_duration_amount,
        free_trial_duration_unit: product.free_trial_duration_unit,
        should_include_last_post: product.should_include_last_post,
        should_show_all_posts: product.should_show_all_posts,
        block_access_after_membership_cancellation: product.block_access_after_membership_cancellation,
        duration_in_months: product.duration_in_months,
        subscription_duration: product.subscription_duration,
        collaborating_user: collaborator.present? ? UserPresenter.new(user: collaborator).author_byline_props : nil,
        is_multiseat_license: product.is_multiseat_license,
        call_limitation_info: call_limitation_info_props,
        cancellation_discount: cancellation_discount.present? ? {
          discount:
            cancellation_discount.is_cents? ?
            { type: "fixed", cents: cancellation_discount.amount_cents } :
            { type: "percent", percents: cancellation_discount.amount_percentage },
          duration_in_billing_cycles: cancellation_discount.duration_in_billing_cycles,
        } : nil,
        default_offer_code: product.default_offer_code ? {
          id: product.default_offer_code.external_id,
          code: product.default_offer_code.code,
          name: product.default_offer_code.name.presence || "",
          discount: product.default_offer_code.discount,
        } : nil,
        public_files: product.alive_public_files.attached.map { PublicFilePresenter.new(public_file: _1).props },
        audio_previews_enabled: Feature.active?(:audio_previews, product.user),
        community_chat_enabled: Feature.active?(:communities, product.user) ? product.community_chat_enabled? : nil,
      }
    end

    def variants_props
      product.alive_variants.in_order.map do |variant|
        props = {
          id: variant.external_id,
          name: variant.name || "",
          description: variant.description || "",
          max_purchase_count: variant.max_purchase_count,
          integrations: Integration::ALL_NAMES.index_with { |name| variant.find_integration_by_name(name).present? },
          rich_content: variant.rich_content_json,
          sales_count_for_inventory: variant.max_purchase_count? ? variant.sales_count_for_inventory : 0,
          active_subscribers_count: variant.active_subscribers_count,
        }
        props[:duration_in_minutes] = variant.duration_in_minutes if product.native_type == Link::NATIVE_TYPE_CALL
        if product.native_type == Link::NATIVE_TYPE_MEMBERSHIP
          props.merge!(
            customizable_price: !!variant.customizable_price,
            recurrence_price_values: variant.recurrence_price_values(for_edit: true),
            apply_price_changes_to_existing_memberships: variant.apply_price_changes_to_existing_memberships?,
            subscription_price_change_effective_date: variant.subscription_price_change_effective_date,
            subscription_price_change_message: variant.subscription_price_change_message,
          )
        else
          props[:price_difference_cents] = variant.price_difference_cents
        end
        props
      end
    end

    def availabilities_props
      return [] unless product.native_type == Link::NATIVE_TYPE_CALL

      product.call_availabilities.map do |availability|
        {
          id: availability.external_id,
          start_time: availability.start_time.iso8601,
          end_time: availability.end_time.iso8601,
        }
      end
    end

    def call_limitation_info_props
      return nil unless product.native_type == Link::NATIVE_TYPE_CALL && product.call_limitation_info.present?

      {
        minimum_notice_in_minutes: product.call_limitation_info.minimum_notice_in_minutes,
        maximum_calls_per_day: product.call_limitation_info.maximum_calls_per_day,
      }
    end

    def custom_domain_verification_status
      custom_domain = product.custom_domain
      return nil if custom_domain.blank?

      domain = custom_domain.domain
      if custom_domain.verified?
        {
          success: true,
          message: "#{domain} domain is correctly configured!",
        }
      else
        {
          success: false,
          message: "Domain verification failed. Please make sure you have correctly configured the DNS record for #{domain}.",
        }
      end
    end
end
