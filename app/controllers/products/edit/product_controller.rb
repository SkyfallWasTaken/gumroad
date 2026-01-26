# frozen_string_literal: true

class Products::Edit::ProductController < Products::Edit::BaseController
  def edit
    set_title

    ai_generated = params[:ai_generated] == "true"

    render inertia: "Products/Edit/Product", props: all_tab_props(ai_generated:).merge(active_tab: "product")
  end

  def update
    begin
      ActiveRecord::Base.transaction do
        update_product_settings
      end
    rescue ActiveRecord::RecordNotSaved, ActiveRecord::RecordInvalid, Link::LinkInvalid => e
      error_message = extract_error_message(e)
      return handle_save_error(error_message, edit_link_path(@product.unique_permalink))
    end

    warning = invalid_offer_codes_warning
    if warning
      return redirect_back fallback_location: edit_link_path(@product.unique_permalink),
                           warning: warning
    end

    redirect_back fallback_location: edit_link_path(@product.unique_permalink),
                  notice: "Changes saved!"
  end

  private
    def update_product_settings
      @product.assign_attributes(product_permitted_params.except(
        :description,
        :cancellation_discount,
        :custom_button_text_option,
        :custom_summary,
        :custom_attributes,
        :file_attributes,
        :covers,
        :refund_policy,
        :product_refund_policy_enabled,
        :seller_refund_policy_enabled,
        :integrations,
        :variants,
        :shipping_destinations,
        :availabilities,
        :custom_domain,
        :call_limitation_info,
        :installment_plan,
        :community_chat_enabled,
        :default_offer_code_id,
        :public_files
      ))

      @product.description = SaveContentUpsellsService.new(
        seller: @product.user,
        content: product_permitted_params[:description],
        old_content: @product.description_was
      ).from_html

      @product.skus_enabled = false
      save_custom_settings
      save_refund_policy
      save_covers_and_integrations
      update_variants
      update_physical_product_settings
      update_call_settings
      update_membership_settings
      update_offer_code_settings
      save_public_files
      finalize_save
    end

    def save_custom_settings
      @product.save_custom_button_text_option(product_permitted_params[:custom_button_text_option]) unless product_permitted_params[:custom_button_text_option].nil?
      @product.save_custom_summary(product_permitted_params[:custom_summary]) unless product_permitted_params[:custom_summary].nil?
      @product.save_custom_attributes((product_permitted_params[:custom_attributes] || []).filter { _1[:name].present? || _1[:description].present? })
    end

    def save_refund_policy
      return if current_seller.account_level_refund_policy_enabled?

      @product.product_refund_policy_enabled = product_permitted_params[:product_refund_policy_enabled]
      if product_permitted_params[:refund_policy].present? && product_permitted_params[:product_refund_policy_enabled]
        @product.find_or_initialize_product_refund_policy.update!(product_permitted_params[:refund_policy])
      end
    end

    def save_covers_and_integrations
      @product.reorder_previews((product_permitted_params[:covers] || []).map.with_index.to_h)
      Product::SaveIntegrationsService.perform(@product, product_permitted_params[:integrations])
    end

    def update_variants
      variant_category = @product.variant_categories_alive.first
      variants = product_permitted_params[:variants] || []

      if variants.any? || @product.is_tiered_membership?
        variant_category_params = variant_category.present? ?
          { id: variant_category.external_id, name: variant_category.title } :
          { name: @product.is_tiered_membership? ? "Tier" : "Version" }

        Product::VariantsUpdaterService.new(
          product: @product,
          variants_params: [{ **variant_category_params, options: variants }],
        ).perform
      elsif variant_category.present?
        Product::VariantsUpdaterService.new(
          product: @product,
          variants_params: [{ id: variant_category.external_id, options: nil }]
        ).perform
      end
    end

    def update_physical_product_settings
      return unless @product.is_physical

      @product.save_shipping_destinations!(product_permitted_params[:shipping_destinations] || [])
      update_removed_file_attributes
    end

    def update_removed_file_attributes
      current = @product.file_info_for_product_page.keys.map(&:to_s)
      updated = (product_permitted_params[:file_attributes] || []).map { _1[:name] }
      @product.add_removed_file_info_attributes(current - updated)
    end

    def update_call_settings
      return unless @product.native_type == Link::NATIVE_TYPE_CALL

      update_availabilities
      update_call_limitation_info
    end

    def update_availabilities
      existing_availabilities = @product.call_availabilities
      availabilities_to_keep = []

      (product_permitted_params[:availabilities] || []).each do |availability_params|
        availability = existing_availabilities.find { _1.id == availability_params[:id] } || @product.call_availabilities.build
        availability.update!(availability_params.except(:id))
        availabilities_to_keep << availability
      end

      (existing_availabilities - availabilities_to_keep).each(&:destroy!)
    end

    def update_call_limitation_info
      @product.call_limitation_info.update!(product_permitted_params[:call_limitation_info])
    end

    def update_membership_settings
      if Feature.active?(:cancellation_discounts, @product.user) && (product_permitted_params[:cancellation_discount].present? || @product.cancellation_discount_offer_code.present?)
        begin
          Product::SaveCancellationDiscountService.new(@product, product_permitted_params[:cancellation_discount]).perform
        rescue ActiveRecord::RecordInvalid => e
          raise Link::LinkInvalid, e.record.errors.full_messages.first
        end
      end

      if @product.native_type === Link::NATIVE_TYPE_COFFEE
        @product.suggested_price_cents = product_permitted_params[:variants].map { _1[:price_difference_cents] }.max
      end

      update_installment_plan
      update_custom_domain
    end

    def update_installment_plan
      return unless @product.eligible_for_installment_plans?

      if @product.installment_plan && product_permitted_params[:installment_plan].present?
        @product.installment_plan.assign_attributes(product_permitted_params[:installment_plan])
        return unless @product.installment_plan.changed?
      end

      @product.installment_plan&.destroy_if_no_payment_options!
      @product.reset_installment_plan

      if product_permitted_params[:installment_plan].present?
        @product.create_installment_plan!(product_permitted_params[:installment_plan])
      end
    end

    def update_custom_domain
      if product_permitted_params[:custom_domain].present?
        custom_domain = @product.custom_domain || @product.build_custom_domain
        custom_domain.domain = product_permitted_params[:custom_domain]
        custom_domain.verify(allow_incrementing_failed_verification_attempts_count: false)
        custom_domain.save!
      elsif product_permitted_params[:custom_domain] == "" && @product.custom_domain.present?
        @product.custom_domain.mark_deleted!
      end
    end

    def update_offer_code_settings
      default_offer_code_id = product_permitted_params[:default_offer_code_id]
      return @product.default_offer_code = nil if default_offer_code_id.blank?

      offer_code = @product.user.offer_codes.alive.find_by_external_id!(default_offer_code_id)

      raise Link::LinkInvalid, "Offer code cannot be expired" if offer_code.inactive?
      raise Link::LinkInvalid, "Offer code must be associated with this product or be universal" unless valid_for_product?(offer_code)

      @product.default_offer_code = offer_code
    rescue ActiveRecord::RecordNotFound
      raise Link::LinkInvalid, "Invalid offer code"
    end

    def valid_for_product?(offer_code)
      offer_code.universal? || @product.offer_codes.where(id: offer_code.id).exists?
    end

    def save_public_files
      @product.description = SavePublicFilesService.new(
        resource: @product,
        files_params: product_permitted_params[:public_files],
        content: @product.description
      ).process
    end

    def finalize_save
      @product.is_licensed = @product.has_embedded_license_key?
      @product.is_multiseat_license = false unless @product.is_licensed
      @product.save!

      toggle_community_chat!(product_permitted_params[:community_chat_enabled])
      Product::SavePostPurchaseCustomFieldsService.new(@product).perform
    end

    def toggle_community_chat!(enabled)
      return unless Feature.active?(:communities, current_seller)
      return if [Link::NATIVE_TYPE_COFFEE, Link::NATIVE_TYPE_BUNDLE].include?(@product.native_type)

      @product.toggle_community_chat!(enabled)
    end

    def extract_error_message(error)
      if @product.errors.details[:custom_fields].present?
        "You must add titles to all of your inputs"
      else
        @product.errors.full_messages.first || error.message
      end
    end
end
