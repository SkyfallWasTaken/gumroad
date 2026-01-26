# frozen_string_literal: true

class ProductPresenter::Edit::ShareTabProps
  attr_reader :product, :pundit_user

  def initialize(product:, pundit_user:)
    @product = product
    @pundit_user = pundit_user
  end

  def props
    profile_sections = product.user.seller_profile_products_sections

    {
      is_listed_on_discover: product.recommendable?,
      profile_sections: profile_sections.map do |section|
        {
          id: section.external_id,
          header: section.header || "",
          product_names: section.product_names,
          default: section.add_new_products,
        }
      end,
      taxonomies: Discover::TaxonomyPresenter.new.taxonomies_for_nav,
      product: product_props(profile_sections),
    }
  end

  private
    def product_props(profile_sections)
      {
        section_ids: profile_sections.filter_map { |section| section.external_id if section.shown_products.include?(product.id) },
        taxonomy_id: product.taxonomy_id&.to_s,
        tags: product.tags.pluck(:name),
        display_product_reviews: product.display_product_reviews,
        is_adult: product.is_adult,
        discover_fee_per_thousand: product.discover_fee_per_thousand,
      }
    end
end
