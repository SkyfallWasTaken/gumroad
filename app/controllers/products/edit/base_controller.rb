# frozen_string_literal: true

class Products::Edit::BaseController < Sellers::BaseController
  include FetchProductByUniquePermalink

  layout "inertia"

  skip_before_action :check_suspended

  before_action :fetch_product_by_unique_permalink
  before_action :authorize_product
  before_action :redirect_if_bundle

  private
    def authorize_product
      authorize @product, :update?
    end

    def redirect_if_bundle
      redirect_to bundle_path(@product.external_id) if @product.is_bundle?
    end

    def set_title
      @title = @product.name
    end

    def base_props
      @base_props ||= ProductPresenter::Edit::BaseProps.new(product: @product, pundit_user:).props
    end

    def merge_props(*tab_props_list)
      result = base_props.deep_dup
      tab_props_list.each do |tab_props|
        result = result.merge(tab_props.except(:product))
        merge_product_props(result, tab_props[:product] || {})
      end
      result
    end

    def merge_product_props(result, new_product_props)
      current_product = result[:product] || {}
      new_product_props.each do |key, value|
        if key == :variants && current_product[:variants].present? && value.is_a?(Array)
          current_product[:variants] = merge_variants(current_product[:variants], value)
        else
          current_product[key] = value
        end
      end
      result[:product] = current_product
    end

    def merge_variants(existing_variants, new_variants)
      new_by_id = new_variants.index_by { |v| v[:id].to_s }

      merged = existing_variants.map do |existing|
        incoming = new_by_id[existing[:id].to_s]
        incoming ? existing.merge(incoming) : existing
      end

      existing_ids = existing_variants.map { |v| v[:id].to_s }.to_set
      merged + new_variants.reject { |v| existing_ids.include?(v[:id].to_s) }
    end

    def all_tab_props(ai_generated: false)
      merge_props(
        ProductPresenter::Edit::ProductTabProps.new(product: @product, pundit_user:, ai_generated:).props,
        ProductPresenter::Edit::ContentTabProps.new(product: @product, pundit_user:).props,
        ProductPresenter::Edit::ShareTabProps.new(product: @product, pundit_user:).props,
        ProductPresenter::Edit::ReceiptTabProps.new(product: @product, pundit_user:).props
      )
    end

    def product_permitted_params
      @_product_permitted_params ||= params.permit(policy(@product).product_permitted_attributes)
    end

    def handle_save_error(error_message, redirect_path)
      redirect_to redirect_path, inertia: { errors: { base: [error_message] } }
    end

    def invalid_offer_codes_warning
      invalid_currency_offer_codes = @product.product_and_universal_offer_codes.reject do |offer_code|
        offer_code.is_currency_valid?(@product)
      end.map(&:code)
      invalid_amount_offer_codes = @product.product_and_universal_offer_codes.reject { _1.is_amount_valid?(@product) }.map(&:code)

      all_invalid_offer_codes = (invalid_currency_offer_codes + invalid_amount_offer_codes).uniq
      return nil if all_invalid_offer_codes.empty?

      has_currency_issues = invalid_currency_offer_codes.any?
      has_amount_issues = invalid_amount_offer_codes.any?

      if has_currency_issues && has_amount_issues
        issue_description = "#{"has".pluralize(all_invalid_offer_codes.count)} currency mismatches or would discount this product below #{@product.min_price_formatted}"
      elsif has_currency_issues
        issue_description = "#{"has".pluralize(all_invalid_offer_codes.count)} currency #{"mismatch".pluralize(all_invalid_offer_codes.count)} with this product"
      else
        issue_description = "#{all_invalid_offer_codes.count > 1 ? "discount" : "discounts"} this product below #{@product.min_price_formatted}, but not to #{MoneyFormatter.format(0, @product.price_currency_type.to_sym, no_cents_if_whole: true, symbol: true)}"
      end

      "The following offer #{"code".pluralize(all_invalid_offer_codes.count)} #{issue_description}: #{all_invalid_offer_codes.join(", ")}. Please update #{all_invalid_offer_codes.length > 1 ? "them or they" : "it or it"} will not work at checkout."
    end
end
